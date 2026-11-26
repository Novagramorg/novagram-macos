Times are wall-clock microseconds per operation. Decoder columns list original / native / forced fallback; pipeline columns list original / native.

## final

| Workload | Forward µs | Reversed µs | Native less time, forward / reversed |
| --- | ---: | ---: | ---: |
| commands | 3.0276 / 0.2655 / 0.3073 | 2.9564 / 0.2727 / 0.3085 | 91.2% / 90.8% |
| empty | 0.0164 / 0.0023 / 0.0027 | 0.0166 / 0.0020 / 0.0020 | 85.8% / 87.7% |
| mixed_1024 | 22.5351 / 1.4431 / 1.4911 | 22.6312 / 1.4071 / 1.4740 | 93.6% / 93.8% |
| mixed_256 | 5.6632 / 0.3978 / 0.4420 | 5.4865 / 0.3976 / 0.4337 | 93.0% / 92.8% |
| mixed_64 | 1.4583 / 0.1514 / 0.2003 | 1.4375 / 0.1630 / 0.2124 | 89.6% / 88.7% |
| numbers | 5.4119 / 0.4029 / 0.4556 | 5.3088 / 0.3893 / 0.4383 | 92.6% / 92.7% |
| one | 0.0308 / 0.0133 / 0.0575 | 0.0308 / 0.0143 / 0.0619 | 56.9% / 53.5% |
| short | 0.2037 / 0.0544 / 0.1017 | 0.1837 / 0.0528 / 0.1017 | 73.3% / 71.3% |

## pipeline

| Workload | Forward µs | Reversed µs | Native less time, forward / reversed |
| --- | ---: | ---: | ---: |
| decode_parse_compact_curves | 24.3819 / 15.4804 | 24.3554 / 15.9769 | 36.5% / 34.4% |
| decode_parse_compact_lines | 15.5506 / 10.3019 | 15.7792 / 10.6542 | 33.8% / 32.5% |
| decode_parse_fractional_curves | 41.0823 / 25.8894 | 41.3915 / 26.1362 | 37.0% / 36.9% |
| decode_parse_integer_curves | 21.1660 / 13.6387 | 20.8185 / 13.8575 | 35.6% / 33.4% |
| decode_parse_integer_lines | 16.4450 / 11.4827 | 15.8740 / 11.4054 | 30.2% / 28.2% |
| decode_parse_short | 1.0977 / 0.8617 | 1.0987 / 0.9002 | 21.5% / 18.1% |
| draw_fractional_curves | 13.1336 / 13.1865 | 12.7099 / 12.7504 | -0.4% / -0.3% |
| draw_integer_curves | 13.1265 / 13.1851 | 12.6583 / 12.5832 | -0.4% / 0.6% |
| draw_integer_lines | 84.6522 / 84.7128 | 80.7572 / 80.5389 | -0.1% / 0.3% |
| draw_short | 1.6292 / 1.6228 | 1.5312 / 1.5471 | 0.4% / -1.0% |
| parse_exponents | 21.6236 / 22.6181 | 21.3619 / 21.3379 | -4.6% / 0.1% |
| parse_fractional_curves | 23.2629 / 24.4013 | 22.9789 / 23.8340 | -4.9% / -3.7% |
| parse_integer_curves | 12.1146 / 12.7289 | 12.2536 / 12.9079 | -5.1% / -5.3% |
| parse_integer_lines | 10.6092 / 10.9746 | 10.8267 / 10.7544 | -3.4% / 0.7% |
| parse_long_numeric | 20.4390 / 20.8644 | 19.7457 / 20.5944 | -2.1% / -4.3% |
| parse_short | 0.7481 / 0.7424 | 0.7156 / 0.7342 | 0.8% / -2.6% |
| placeholder_image_compact_curves | 227.8962 / 215.7087 | 212.1052 / 203.0210 | 5.3% / 4.3% |
| placeholder_image_compact_lines | 102.3733 / 97.4590 | 97.4092 / 92.5652 | 4.8% / 5.0% |
| placeholder_image_fractional_curves | 58.1775 / 43.4727 | 57.4902 / 42.6515 | 25.3% / 25.8% |
| placeholder_image_integer_curves | 39.0104 / 31.3635 | 37.8623 / 30.8048 | 19.6% / 18.6% |
| placeholder_image_integer_lines | 79.3531 / 74.6740 | 77.6581 / 71.6154 | 5.9% / 7.8% |
| placeholder_image_short | 4.2369 / 3.8740 | 4.2965 / 4.0767 | 8.6% / 5.1% |
| rounded_control | 50.4873 / 50.6042 | 48.1488 / 47.5098 | -0.2% / 1.3% |
| sticker_construct_compact_curves | 274.8025 / 263.9796 | 252.1746 / 244.3604 | 3.9% / 3.1% |
| sticker_construct_compact_lines | 148.3058 / 142.8233 | 136.1325 / 131.5075 | 3.7% / 3.4% |
| sticker_construct_fractional_curves | 102.2873 / 86.4156 | 97.4533 / 82.2094 | 15.5% / 15.6% |
| sticker_construct_integer_curves | 83.3427 / 74.3750 | 82.3967 / 74.4881 | 10.8% / 9.6% |
| sticker_construct_integer_lines | 121.0315 / 115.7248 | 116.5792 / 113.8169 | 4.4% / 2.4% |
| sticker_construct_short | 48.2206 / 47.1975 | 43.5967 / 42.8171 | 2.1% / 1.8% |
| unchanged_control | 0.0689 / 0.0728 | 0.0665 / 0.0714 | -5.8% / -7.4% |
