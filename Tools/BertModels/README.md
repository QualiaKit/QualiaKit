# Prepare external BERT models

`prepare.py` packages a **local, already converted Core ML sequence classifier**
and a standard Hugging Face BERT WordPiece tokenizer for `BertQualiaAnalyzer`.
Install `requirements-prepare.txt` in an isolated Python environment, then use
`python prepare.py --help`. It never downloads or publishes a model. Supply the
real ordered label mapping and training preprocessing; unsupported tokenizer or
tensor contracts fail explicitly.

The output directory belongs to the consuming application. Keep private models,
vocabularies, validation texts and label mappings outside the public repository
or in an ignored local directory. This public tool contains no application model
names, weights, vocabulary or training data.

[BERT runtime contract](../../Documentation/BertRuntime.md) covers all options,
supported formats and integration. This does not train, convert or qualify a
model's semantic quality.

`generate_fixtures.py` creates tiny public arithmetic fixtures and reference token
arrays with transformers 4.57.1 and tokenizers 0.22.2, in addition to the preparation
dependencies. Use a new `--out` directory; it refuses to overwrite versioned
fixtures. The three checked-in models have no learned weights. Core ML output is
compared with separately computed analytical values. Run the Swift test suite for
the tokenization, inference, cancellation and asset-integrity checks.
