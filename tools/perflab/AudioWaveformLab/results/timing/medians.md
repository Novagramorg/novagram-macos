Medians are microseconds per operation. Negative savings mean the current variant took longer.

| Samples | Width | Workload | Original → current, forward | Original → current, reverse | Less time, forward / reverse |
| ---: | ---: | --- | ---: | ---: | ---: |
| 100 | 40 | construct_and_draw | 46.483 → 46.807 | 48.808 → 49.550 | -0.7% / -1.5% |
| 100 | 40 | construct_only | 16.063 → 15.989 | 15.926 → 16.848 | 0.5% / -5.8% |
| 100 | 40 | reveal_pair_draw | 26.064 → 25.642 | 26.425 → 25.103 | 1.6% / 5.0% |
| 100 | 40 | same_color_pair_draw | 28.458 → 27.886 | 30.386 → 29.724 | 2.0% / 2.2% |
| 100 | 200 | construct_and_draw | 134.053 → 134.521 | 147.275 → 144.866 | -0.3% / 1.6% |
| 100 | 200 | construct_only | 15.724 → 16.115 | 16.259 → 17.247 | -2.5% / -6.1% |
| 100 | 200 | reveal_pair_draw | 99.205 → 98.620 | 104.616 → 104.139 | 0.6% / 0.5% |
| 100 | 200 | same_color_pair_draw | 114.981 → 114.103 | 123.778 → 119.849 | 0.8% / 3.2% |
| 1000 | 40 | construct_and_draw | 49.728 → 47.382 | 51.271 → 50.664 | 4.7% / 1.2% |
| 1000 | 40 | construct_only | 16.082 → 16.107 | 16.475 → 16.994 | -0.2% / -3.2% |
| 1000 | 40 | reveal_pair_draw | 28.118 → 24.695 | 28.177 → 25.470 | 12.2% / 9.6% |
| 1000 | 40 | same_color_pair_draw | 30.899 → 27.265 | 33.204 → 29.943 | 11.8% / 9.8% |
| 1000 | 200 | construct_and_draw | 160.041 → 159.608 | 165.655 → 165.044 | 0.3% / 0.4% |
| 1000 | 200 | construct_only | 15.973 → 16.079 | 17.111 → 17.192 | -0.7% / -0.5% |
| 1000 | 200 | reveal_pair_draw | 122.872 → 118.219 | 129.085 → 127.251 | 3.8% / 1.4% |
| 1000 | 200 | same_color_pair_draw | 140.180 → 138.639 | 149.584 → 146.258 | 1.1% / 2.2% |
