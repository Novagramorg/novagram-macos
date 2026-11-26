from pathlib import Path
import json
import sys

baseline, candidate = [json.loads(Path(path).read_text()) for path in sys.argv[1:]]
for key in ['rows', 'posts_per_batch', 'batches']:
    assert baseline[key] == candidate[key], key
rows = baseline['rows']
posts = baseline['posts_per_batch']
assert len(baseline['results']) == len(candidate['results']) == 5
for before, after in zip(baseline['results'], candidate['results']):
    scenario = before['scenario']
    assert scenario == after['scenario']
    if scenario.startswith('plain_unrelated'):
        expected_before, expected_after = rows * posts, 0
    elif scenario == 'plain_row_frame':
        expected_before, expected_after = (rows + 1) * posts, posts
    else:
        expected_before = expected_after = rows * posts
    assert before['callbacks_per_batch'] == [expected_before] * baseline['batches'], scenario
    assert after['callbacks_per_batch'] == [expected_after] * candidate['batches'], scenario
    assert before['independent_callbacks'] == 0, scenario
    assert after['independent_callbacks'] == rows, scenario
    print(f"{scenario}: {before['median_ns_per_post']:.1f} -> {after['median_ns_per_post']:.1f} ns/post; "
          f"{expected_before} -> {expected_after} callbacks/batch")
