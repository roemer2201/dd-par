# ddpar
Attempting scripted parallel dd execution.

## Usecases
### local
#### uncrompressed

| | clone (check) || backup (check) | restore (check) |
|----------|----------|-|----------|----------|
| block dev | :heavy_check_mark: (:stop_sign:) || :heavy_check_mark: (:heavy_check_mark:) | :heavy_check_mark: (:heavy_check_mark:) |
| file | :stop_sign: (:stop_sign:) || :heavy_check_mark: (:heavy_check_mark:) | :heavy_check_mark: (:heavy_check_mark:) |

#### compressed
| | clone (check) || backup gzip (check) | restore gzip (check) |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: (:stop_sign:) || :heavy_check_mark: (:heavy_check_mark:) | :stop_sign: (:stop_sign:) |
| file | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |

<br>

### remote - ssh
#### uncompressed 
|  | clone || backup (check) | restore (check) |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |
| file | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |

#### local [de]compression
| | clone || backup gzip (check) | restore gzip (check) |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |
| file | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |

#### remote [de]compression
| | clone || backup gzip (check) | restore gzip (check) |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |
| file | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |

<br>

### remote - netcat
#### uncompressed 
| | clone || backup (check) | restore (check) |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |
| file | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |

#### local [de]compression
| | clone || backup gzip (check) | restore gzip (check) |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |
| file | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |

#### remote [de]compression
| | clone || backup gzip (check) | restore gzip (check) |
|----------|----------|-|----------|----------|
| block dev | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |
| file | :stop_sign: (:stop_sign:) || :stop_sign: (:stop_sign:) | :stop_sign: (:stop_sign:) |

## To Do
- check read/write permissions for $SOURCE, $BACKUP_BASE and $DESTINATION
- ddpar-check.sh: Add if-statement for checking if a backup as been created with a sha256sum
- ddpar.sh: Add option to give a backup a custom BASE_NAME
- use this BASE_NAME as path for checksum files for clones (where user request checksuming)
- echo a message if no reasonable alternative number of threads/jobs could be calculated
- when compressing an image and option -c (checksum) is given, should the script calculate the checksum of both, the raw file and the compressed file? (Currently only basefile's checksum is calculated.)
- Code to make missing features work
