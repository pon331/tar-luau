# tar-luau
A collection of fast TAR archivers for Luau

# Features
- Native codegen: `--!native` for maximum speed
- Strict typing: `--!strict`, full type annotations
- All primary TAR formats supported - `Pax`, `GNU`, `Ustar`, `V7`
- Both `tar32` and `tar64` supported
- Identical API for all modules

# Modules

| Module | Format | Name limit | Numeric range |
|---|---|---|---|
| `tar32v7` / `tar64v7` | v7 (no prefix) | 100 chars | sizes <= 4 GiB − 1 / <= 8 GiB − 1 |
| `tar32ustar` / `tar64ustar` | POSIX ustar | 256 chars (155/100 prefix split) | sizes <= 4 GiB − 1 / <= 8 GiB − 1 |
| `tar32gnu` / `tar64gnu` | GNU | unlimited (`././@LongLink` type `L`) | + GNU base-256 decoding |
| `tar32pax` / `tar64pax` | POSIX pax | unlimited (`path` records) | + `size` records decoding |

# API

## `Tar.Tar(Files: { [string]: buffer }) -> buffer`
Creates a new TAR archive from files in format `{ [filepath] = filebuffer }`
Returns TAR archive buffer

## `Tar.Untar(Data: buffer) -> { [string]: buffer }`
Extracts TAR archive
Returns files in format `{ [filepath] = filebuffer }`

# Performance
Measured with `luau-cli`, `--codegen` and `-O2`

1.4MB mixed content:

|Tar|Untar|
|---|---|
|5.5–6.2 GB/s |	6.8–7.3 GB/s |

# Example usage

Creating and extracting TAR archive (ustar32)
```luau
const Tar = require(path.to.tar32ustar)

const Archive = {
  test = buffer.fromstring("test"),
  dir = buffer.create(0),
  ["dir/inner"] = buffer.fromstring("inner")
}

const Archived = Tar.Tar(Archive)

const Extracted = Tar.Untar(Archived)
print(Extracted)
-- outputs this:
--[[
{
  ["dir"] = buffer { Size = 0 },
  ["dir/inner"] = buffer { Size = 5 },
  ["test"] = buffer { Size = 4 }
} 
]]
```
