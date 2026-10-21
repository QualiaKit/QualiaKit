#!/usr/bin/env python3
"""Build DocC for all current public products and audit compiler-derived coverage."""
import argparse
import collections
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import unquote,urlparse

ROOT=Path(__file__).resolve().parents[2]
GUIDES=ROOT/'docs'
CATALOG=ROOT/'Sources/QualiaKit/Documentation.docc'
TYPE_CONTRACTS=json.loads((Path(__file__).parent/'reference_contracts.json').read_text())
# Contracts apply to every entry in a layer, including inherited/synthesized API
# detail pages. Never count these as hand-written source documentation.
CONTRACTS={
 'Analysis': ('ChoosingAnAnalyzer', 'Analyzer contracts', 'Analyzers are Sendable and expose stable language, dimension, signal and context capabilities. Analysis is asynchronous and cancellable; an observation preserves request identity and actual analyzer provenance. Operational failure throws rather than returning neutral. Apple preview accepts one English paragraph without history and emits valence only. Inference must not block MainActor.'),
 'Domain': ('ChoosingAnAnalyzer', 'Domain values', 'These model-agnostic Sendable values describe inputs, languages, observations and declared capabilities. Text and caller IDs can be sensitive. Scores are finite normalized values; missing evidence differs from zero. Throwing constructors validate their documented invariants. Values perform no I/O, rendering or implicit semantic mapping. Codable does not grant permission to log or persist text.'),
 'Diagnostics': ('PrivacyAndDataFlow', 'Redacted diagnostics', 'Diagnostics are opt-in and contain no raw text, input IDs, tensors or arbitrary adapter descriptions. Metadata identities use SHA-256 fingerprints. Sinks must be concurrency-safe, prompt and bounded. Report formatting performs no I/O and retains a bounded snapshot. Closed error categories preserve recoverability without exporting sensitive associated strings.'),
 'Haptics': ('BuildingHapticPatterns', 'Physical rendering', 'Descriptors are validated immutable Sendable values; rendering protocols and implementations are MainActor-isolated. Capability flags must be checked before playback. Ambient loops and independent accents use distinct channels. Session-owned effect IDs and cleanup protect other owners. Throwing renderer calls can partially succeed: inspect activeEffects and the typed error; do not equate a planned command with physical success. Physical sensation requires device testing.'),
 'Heartbeat': ('BuildingHapticPatterns', 'Heartbeat planning', 'Heartbeat configuration and pattern generation are deterministic value operations. Validate finite ranges, thresholds and durations at construction. A stable owned effect is updated within its original physical deadline. Use the public factory instead of copying rhythm math. Scores describe intended content experience; they never measure a person’s pulse or fear.'),
 'Preparation': ('SessionsAndContext', 'Language and context', 'Preparation resolves language according to an explicit policy and bounds generic context before inference. Detection confidence and allowed languages must be supplied deliberately. Eviction preserves whole fragments and current text; current text exceeding bounds throws. Model token truncation is separate. Resolvers/detectors are Sendable; custom implementations preserve cancellation and avoid blocking MainActor. Diagnostics expose counts and categories only.'),
 'Reaction': ('CreatingReactionPolicies', 'Policies and safety', 'Policies are pure Sendable mappings and cannot retain or invoke renderers. Validate analyzer and hardware compatibility at installation. A plan preserves or explicitly updates applied reaction state and orders commands. The MainActor executor enforces preferences, ownership and physical deadlines, reconciles partial failure, and exposes attempted outcomes. Custom rationale strings must never contain input text; the redacted report fingerprints identities and omits facts.'),
 'Scene': ('Architecture', 'Temporal state', 'Reducers are deterministic Sendable value operations with an injected monotonic instant. Continuous signals accumulate; event evidence applies only to the current transition. Missing evidence is distinct from zero. Scene phase is derived state, not a model prediction. Public constructors reject invalid normalized state, revisions or inconsistent event evidence; reducers must preserve these invariants.'),
 'Session': ('SessionsAndContext', 'Session orchestration', 'QualiaSession is an actor; its factories install MainActor renderers and validate capabilities. One session owns one accepted event stream and retained history. A newer request invalidates older work, including cancellation-ignoring analyzers. Use unique accepted IDs and empty external context. Await suspend/resume/reset at host lifecycle boundaries. Cleanup failure remains visible and blocks unsafe continuation; responses distinguish planned commands from attempted execution.'),
 'SwiftUI': ('SessionsAndContext', 'SwiftUI integration', 'SwiftUI helpers operate with an explicitly retained session. Accepted events use stable identity; draft typing uses a separate debounced session with language detection. Result callbacks run on MainActor. View recomputation must not recreate sessions. The host owns suspend/resume/reset and must await cleanup before admitting a new event.'),
 'QualiaTesting': ('TestingYourIntegration', 'Deterministic testing', 'Test doubles use public QualiaKit contracts and never establish physical sensation or semantic accuracy. FixtureAnalyzer looks up authored observations by ID. ControlledAnalyzer and TestQualiaClock expose cancellation-aware barriers; release pending work in teardown. RecordingHapticRenderer and QualiaSessionHarness are MainActor-isolated; clock/diagnostic storage is synchronized. Assert exact ordered commands using an independent oracle, not the implementation under test.'),
 'QualiaCoreML': ('UsingCoreMLModels', 'Local model integration', 'The optional adapter validates local asset inventories, manifests, tensors and output mapping before use. Construction and inference are asynchronous, with mutable Core ML state isolated on the runtime worker. Cancellation and typed failures are preserved; checksum/contract errors never become neutral output. Source URLs must remain local. Declared capabilities and label semantics require independent evaluation, and the repository license grants no external model rights.'),
}

def call(args):
    subprocess.run(args,cwd=ROOT,check=True)

def source_guides():
    result={}
    for path in sorted(GUIDES.glob('*.md')):
        text=path.read_text()
        # Local conceptual links use DocC article resolution in the catalog.
        text=re.sub(r'\[([^\]]+)\]\(([A-Za-z][A-Za-z0-9_]+)\.md\)',lambda m:f'<doc:{m[2]}>',text)
        result[path.name]=text
    return result

def sync_catalog(write=False):
    guides=source_guides()
    landing='# ``QualiaKit``\n\nOn-device semantic observations, temporal state, policies and owned haptic playback.\n\n## Topics\n\n### Integration guides\n\n'+''.join(f'- <doc:{Path(name).stem}>\n' for name in guides)
    files={**guides,'QualiaKit.md':landing}
    for name,text in files.items():
        path=CATALOG/name
        if write: path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text)
        elif not path.exists() or path.read_text()!=text:raise ValueError(f'DocC guide drift: {path}; run build_docs.py --sync')

def layer(symbol,module,by_path):
    if module!='QualiaKit':return module
    # RawRepresentable initializers can be exported without a source location.
    # Bind those generated entries to their nearest declared owning type.
    location=symbol.get('location',{})
    path=symbol['pathComponents'][:-1]
    while not location.get('uri') and path:
        location=by_path.get(tuple(path),{}).get('location',{})
        path=path[:-1]
    uri=unquote(location.get('uri',''))
    match=re.search(r'/Sources/QualiaKit/([^/]+)/',uri)
    if not match or match[1] not in CONTRACTS:raise ValueError('Public symbol has no documented layer: '+str(symbol['pathComponents']))
    return match[1]

def declaration(symbol):
    return ''.join(part['spelling'] for part in symbol.get('declarationFragments',[]))

def abstract(symbol):
    kind=symbol['kind']['identifier'];name=symbol['names']['title'];parent='.'.join(symbol['pathComponents'][:-1])
    comments=symbol.get('docComment',{}).get('lines',[])
    if comments:
        lines=[x['text'] for x in comments]
        return ' '.join(lines[:next((i for i,x in enumerate(lines) if not x.strip()),len(lines))])
    if kind=='swift.init':
        return f'Creates `{parent}` using the declared inputs'+('; construction can fail and must be handled by the caller.' if 'throws' in declaration(symbol) else '.')
    if kind in ['swift.method','swift.type.method']:
        purposes={
          'analyze':'Produces a typed observation for the supplied input; preserve request identity, declared capabilities and cancellation.',
          'record':'Receives one already-redacted diagnostic event; this sink defines retention and I/O behavior.',
          'emit':'Evaluates and records an event only when the sink is enabled.',
          'redacted':'Converts a failure into its recoverable public category without arbitrary associated text.',
          'encode':'Encodes this public value through the supplied Encoder; the host owns storage and privacy policy.',
          'execute':'Attempts the supplied physical command; inspect failure and active effects before committing reaction state.',
          'stopEffects':'Stops effects belonging to the supplied owner and reports incomplete cleanup.',
          'suspend':'Prevents further playback while owned effects are stopped; resumption does not replay prior input.',
          'resume':'Allows new work after suspension without replaying a previous effect.',
          'makePattern':'Creates a validated heartbeat descriptor from public parameters and an explicit maximum duration.',
          'detectLanguage':'Returns language evidence for input text; detection is distinct from declaring model support.',
          'window':'Bounds context by removing whole historical fragments while preserving current text and identity.',
          'prepare':'Prepares the receiver for its next operation, validating its declared input or lifecycle contract.',
          'resolve':'Resolves the declared local model or language source and propagates typed setup failures.',
          'plan':'Computes ordered declarative commands from the transition and context without invoking a renderer.',
          'appliedAmbientState':'Returns the descriptor last successfully applied for the requested effect, if present.',
          'applying':'Returns a reaction-state value containing the supplied applied descriptor.',
          'removingEffect':'Returns a reaction-state value without the requested effect.',
          'validate':'Checks installation-time compatibility before processing can begin.',
          'reduce':'Produces the next temporal transition from the prior state, observation and supplied instant.',
          'process':'Processes one accepted input through the session; newer work may cancel or supersede this operation.',
          'sleep':'Suspends until the clock’s deadline, preserving cancellation.',
          'complete':'Resolves one controlled analyzer request with explicitly supplied output.',
          'clearHistory':'Releases retained test request history without inventing completions.',
          'simulateEngineInterruption':'Exercises interruption behavior without a physical engine.',
          'simulateEngineReset':'Exercises engine reset and recovery rules using the recording renderer.',
          'failNext':'Injects the specified failure into the next applicable renderer operation.',
          'resetHistory':'Clears captured test records while leaving live effect state governed by lifecycle operations.',
          'advance':'Advances deterministic test time and resumes eligible waiters; time must remain monotonic.',
          'cancelAll':'Cancels registered test work so teardown leaves no blocked continuations.',
          'reset':'Resets this receiver’s owned state; session/harness reset also stops owned effects.',
        }
        verb=name.split('(')[0]
        return purposes.get(verb,f'Performs `{name}` under the owning public contract shown below.')
    if kind=='swift.enum.case':return f'Selects the `{name}` case of `{parent}`; its associated values are part of the declared contract.'
    if kind in ['swift.property','swift.type.property']:return f'Exposes `{name}` from `{parent}`; the declaration specifies its value type and mutability.'
    return f'The `{name}` public contract for this layer; use the declared members and the lifecycle, capability and failure rules below.'

def build(output,skip_export=False):
    sync_catalog()
    if not skip_export:
        call(['swift','package','dump-symbol-graph','--minimum-access-level','public','--skip-synthesized-members'])
        call(['swift','package','--package-path','Packages/QualiaCoreML','dump-symbol-graph','--minimum-access-level','public','--skip-synthesized-members'])
    output.mkdir(parents=True,exist_ok=True)
    audit={'format':1,'modules':{},'scope':'QualiaKit, QualiaTesting and QualiaCoreML; compiler-generated conformances and legacy products excluded'}
    with tempfile.TemporaryDirectory(prefix='qualia-docc-',dir=output) as temp:
        temp=Path(temp)
        for module,base in [('QualiaKit',ROOT/'.build/out/symbolgraph'),('QualiaTesting',ROOT/'.build/out/symbolgraph'),('QualiaCoreML',ROOT/'Packages/QualiaCoreML/.build/out/symbolgraph')]:
            graphs=temp/module/'graphs';graphs.mkdir(parents=True)
            symbols={}
            for path in sorted(base.glob(module+'*.symbols.json')):
                if not (path.name==module+'.symbols.json' or path.name.startswith(module+'@')):continue
                shutil.copyfile(path,graphs/path.name)
                for s in json.loads(path.read_text())['symbols']:
                    if s.get('accessLevel')=='public' and s['kind']['identifier']!='swift.extension':symbols[s['identifier']['precise']]=s
            if not symbols:raise ValueError('Missing public symbols for '+module)
            catalog=temp/module/(module+'.docc');shutil.copytree(CATALOG,catalog)
            if module!='QualiaKit':
                (catalog/'QualiaKit.md').unlink()
                (catalog/(module+'.md')).write_text(f'# ``{module}``\n\n{CONTRACTS[module][2]}\n\n## Topics\n\n### Guides\n\n'+''.join(f'- <doc:{Path(p).stem}>\n' for p in source_guides()))
            archive=output/(module+'.doccarchive')
            common=['xcrun','docc','convert',str(catalog),'--additional-symbol-graph-dir',str(graphs),'--output-dir',str(archive),'--fallback-bundle-identifier','org.qualiakit.'+module.lower(),'--warnings-as-errors','--emit-digest']
            call(common)
            # Resolve extension headings using DocC's own disambiguated routes,
            # rather than implementing its overload hashing or guessing names.
            routes={}
            for path in (archive/'data/documentation').rglob('*.json'):
                node=json.loads(path.read_text());external=node.get('metadata',{}).get('externalID')
                if external:routes[external]=node['identifier']['url'].split('/documentation/',1)[1]
            missing=set(symbols)-set(routes)
            if missing:raise ValueError('Public symbols missing DocC routes: '+str(sorted(missing)))
            directory=catalog/'Reference';directory.mkdir()
            by_path={tuple(s['pathComponents']):s for s in symbols.values()}
            for i,(identifier,symbol) in enumerate(sorted(symbols.items())):
                guide,title,contract=CONTRACTS[layer(symbol,module,by_path)]
                if not (GUIDES/(guide+'.md')).is_file():raise ValueError('Missing guide '+guide)
                route=unquote(routes[identifier])
                type_contract=TYPE_CONTRACTS.get(symbol['pathComponents'][0], '')
                if type_contract:
                    contract=type_contract+'\n\n'+contract
                page=f'# ``{route}``\n\n{abstract(symbol)}\n\n## {title}\n\n{contract}\n\nAvailable with this package on iOS 16 and macOS 13 or later. Actor annotations and individual platform availability are shown in the symbol declaration.\n\nSee <doc:{guide}> for setup, capability requirements, typed errors and a compiled consumer example.\n'
                (directory/(f'{i:04d}.md')).write_text(page)
            call(common+['--experimental-documentation-coverage','--coverage-summary-level','brief'])
            audit['modules'][module]={'publicSymbols':len(symbols),'doccRoutes':len(symbols),'sourceCommented':sum(bool(s.get('docComment',{}).get('lines')) for s in symbols.values()),'contractExtensions':len(symbols),'symbolKinds':dict(collections.Counter(s['kind']['identifier'] for s in symbols.values()))}
    (output/'public-api-coverage.json').write_text(json.dumps(audit,indent=2,sort_keys=True)+'\n')
    print(json.dumps(audit,sort_keys=True))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path);p.add_argument('--sync',action='store_true');p.add_argument('--skip-export',action='store_true');args=p.parse_args()
    if args.sync:sync_catalog(write=True)
    elif args.output:build(args.output.resolve(),args.skip_export)
    else:sync_catalog()
