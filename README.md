# ddpar
Attempting scripted parallel dd execution.

## Usecases
### local

| | clone || backup | restore |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: || :heavy_check_mark: | :stop_sign: |
| file | :stop_sign: || :heavy_check_mark: | :stop_sign: |

### remote

| | clone || backup | restore |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: || :stop_sign: | :stop_sign: |
| file | :stop_sign: || :stop_sign: | :stop_sign: |