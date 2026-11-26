from pathlib import Path
import json
import sys

directory = Path(sys.argv[1])
rows = json.loads((directory / 'renders.json').read_text())['results']
assert len(rows) == 24
indexed = {(row['variant'], row['scenario'], row['frame']): row for row in rows}
comparisons = []
for scenario in ['steady', 'resized', 'recolored', 'pause_resume']:
    for frame in [30, 180, 300]:
        a = indexed['baseline', scenario, frame]
        b = indexed['candidate', scenario, frame]
        assert a['sha256'] == b['sha256'], (scenario, frame, 'Pixels differ')
        assert a['particle_pixels'] == b['particle_pixels']
        if scenario == 'pause_resume' and frame == 180:
            assert b['particle_pixels'] == 0
        else:
            assert b['particle_pixels'] > 0, (scenario, frame, 'Blank particle rendering')
        comparisons.append({'scenario': scenario, 'frame': frame, 'identical': True, 'particle_pixels': b['particle_pixels']})
assert indexed['candidate', 'steady', 30]['sha256'] != indexed['candidate', 'steady', 180]['sha256']
output = {'matching_frame_pairs': len(comparisons), 'comparisons': comparisons, 'animated_frames_differ': True, 'pause_drains_particles': True, 'resume_emits_particles': True}
(directory / 'render-validation.json').write_text(json.dumps(output, indent=2) + '\n')
print(json.dumps(output, indent=2))
