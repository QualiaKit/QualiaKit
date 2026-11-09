# Study inputs v1

All JSON is read through the closed/duplicate-key/nonfinite checks in `evidence.py`.
Paths in the CLI are explicit local inputs; the tools do not fetch or collect data.
Each file has exactly the fields described below.

## Dataset

`schemaVersion: 1`, nonempty `version`, `split` (`validation` or `test`), nonempty
`provenance`, `rights`, `removalPolicy`, `sanitization` (`synthetic`, `sanitized`,
`licensed-public`), unique nonempty arrays `annotators` (at least two), `signals`,
`languages`, `lengthBuckets`, and a nonempty `cases` array.

Each case has `id`, `groupID`, `text` (nonempty strings), `context` (array of nonempty
text fragments, may be empty), `language`, `lengthBucket`, `labels`, `annotations`,
`hardNegative`, `productionLike`. Language/bucket must belong to the declared lists.
IDs must be unique. Group related passages under the same `groupID` to prevent
cross-split leakage. Length boundaries and labelling instructions belong to the
reviewed study protocol; do not move cases between buckets after seeing scores.

`labels` maps every declared signal to integer 0 or 1 after adjudication.
`annotations` maps every declared annotator ID to their original complete binary
signal labels. Do not copy adjudicated labels into independent annotations.
`hardNegative` and `productionLike` are booleans; hard negatives have zero labels
for every evaluated signal. Evaluation requires at least one production-like hard
negative and some nonempty context. Unit-test synthetic fixtures may exercise
these flags but are never evidence that a production-like study occurred.

Each required signal×language×length bucket needs both classes. Dataset definitions
(signals/languages/buckets, including order) must agree across splits. Neither
shared IDs/groups nor identical trimmed current texts may cross splits. Human
review is still needed for shared source documents, semantic duplicates and rights.

## Prediction export

`schemaVersion: 1`, exact candidate `identity` (`model`, `policy`, `runtime`, `build`),
`datasetSHA256`, and `rows`. Every dataset ID occurs once, with no extra IDs. Each
row has `id`, `withoutContext`, `withContext`; each mode maps every declared signal
to a finite score in [0,1]. These must be actual model results for the corresponding
mode. Unsupported context cannot be filled by fabricated scores.

## Threshold-selection plan

`schemaVersion: 1`, `identity`, nonempty `thresholdCandidates` (values in [0,1]),
`costs` (each signal maps to `falsePositive` and `falseNegative`, both nonnegative,
not both zero), and these prespecified numeric limits:

- `minimumAgreement`, `minimumF1`, `maximumHardNegativeRate`,
  `minimumContextF1Delta`: [0,1].
- `maximumWarmP95Milliseconds`: positive.

Choose candidate grid, costs and acceptance limits before held-out evaluation.
The generated protocol conforms to the existing admission format. It binds the
exact bytes of both datasets and every selected threshold. Generated measurement
reports are unreviewed; the machine never inserts a reviewer or release approval.
