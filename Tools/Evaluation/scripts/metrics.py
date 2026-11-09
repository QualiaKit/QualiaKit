"""Deterministic binary metrics. No model inference, labels or thresholds are invented."""
import math


def binary(labels, scores, threshold):
    if not labels or len(labels) != len(scores):
        raise ValueError('aligned nonempty labels/scores required')
    if any(type(y) is not int or y not in (0, 1) for y in labels):
        raise ValueError('binary integer labels required')
    if any(type(p) not in (int, float) or not math.isfinite(p) or not 0 <= p <= 1 for p in [*scores, threshold]):
        raise ValueError('finite probabilities and threshold required')
    tp = sum(y == 1 and p >= threshold for y, p in zip(labels, scores))
    fp = sum(y == 0 and p >= threshold for y, p in zip(labels, scores))
    fn = sum(y == 1 and p < threshold for y, p in zip(labels, scores))
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    # Step-integrated PR area (average precision), grouping ties as one threshold.
    groups = {}
    for y, p in zip(labels, scores):
        positives, count = groups.get(p, (0, 0))
        groups[p] = positives + y, count + 1
    positives = sum(labels)
    cumulative_positive = cumulative_count = 0
    area = 0.0
    for score in sorted(groups, reverse=True):
        group_positive, count = groups[score]
        cumulative_positive += group_positive
        cumulative_count += count
        if positives:
            area += group_positive / positives * cumulative_positive / cumulative_count
    ece = 0.0
    for bucket in range(10):
        pairs = [(y, p) for y, p in zip(labels, scores) if min(9, int(p * 10)) == bucket]
        if pairs:
            ece += abs(sum(y for y, _ in pairs) - sum(p for _, p in pairs)) / len(labels)
    return dict(cases=len(labels), precision=precision, recall=recall,
                f1=2 * precision * recall / (precision + recall) if precision + recall else 0.0,
                prAUC=area, calibrationError=ece, truePositives=tp, falsePositives=fp,
                falseNegatives=fn, positives=positives, negatives=len(labels)-positives)


def fleiss_kappa(ratings):
    """Fleiss kappa over case×signal items, fixed number of binary annotators."""
    if not ratings or len(ratings[0]) < 2:
        raise ValueError('at least two independent annotators required')
    n = len(ratings[0])
    if any(len(row) != n or any(type(x) is not int or x not in (0, 1) for x in row) for row in ratings):
        raise ValueError('fixed aligned binary annotators required')
    agreement = sum((sum(row)*(sum(row)-1) + (n-sum(row))*(n-sum(row)-1))/(n*(n-1)) for row in ratings)/len(ratings)
    positive_fraction = sum(map(sum, ratings))/(len(ratings)*n)
    chance = positive_fraction**2 + (1-positive_fraction)**2
    if chance == 1:
        raise ValueError('annotation agreement undefined for constant ratings')
    return (agreement-chance)/(1-chance)


def select_threshold(labels, scores, candidates, false_positive_cost, false_negative_cost):
    if not candidates or any(type(c) not in (int,float) or not math.isfinite(c) or c < 0 for c in [false_positive_cost,false_negative_cost]) or false_positive_cost + false_negative_cost == 0:
        raise ValueError('positive error cost and candidate thresholds required')
    rows = []
    for threshold in sorted(set(candidates)):
        measured = binary(labels, scores, threshold)
        loss = measured['falsePositives']*false_positive_cost + measured['falseNegatives']*false_negative_cost
        rows.append(dict(threshold=threshold, cost=loss, **measured))
    # Fixed tie break prefers fewer false reactions, then a higher threshold.
    winner = min(rows, key=lambda r: (r['cost'], r['falsePositives'], -r['threshold']))
    return winner['threshold'], rows
