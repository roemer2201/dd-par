# ddpar
Attempting scripted parallel dd execution.

## Usecases
### local

| | clone (check) || backup (check) | restore (check) |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: (:stop_sign:) || :heavy_check_mark: (:stop_sign:) | :heavy_check_mark: (:heavy_check_mark:) |
| file | :stop_sign: (:stop_sign:) || :heavy_check_mark: (:stop_sign:) | :heavy_check_mark: (:heavy_check_mark:) |

### remote

| | clone || backup | restore |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: || :stop_sign: | :stop_sign: |
| file | :stop_sign: || :stop_sign: | :stop_sign: |
