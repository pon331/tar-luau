--!strict
--!native
--!optimize 2

const BLOCK_SIZE = 512
const HEADER_SIZE = 512

const NAME_OFFSET = 0
const NAME_LENGTH = 100
const MODE_OFFSET = 100
const MODE_DIGITS = 7
const UID_OFFSET = 108
const UID_DIGITS = 7
const GID_OFFSET = 116
const GID_DIGITS = 7
const SIZE_OFFSET = 124
const SIZE_DIGITS = 11
const MTIME_OFFSET = 136
const MTIME_DIGITS = 11
const CHECKSUM_OFFSET = 148
const CHECKSUM_DIGITS = 6
const CHECKSUM_LENGTH = 8
const TYPE_OFFSET = 156
const GNU_PREFIX_OFFSET = 257
const GNU_PREFIX_LENGTH = 8

const GNU_PREFIX_LOW = 0x6174_7375
const GNU_PREFIX_HIGH = 0x0020_2072
const GNU_PREFIX = "ustar  \0"
const LONG_NAME = "././@LongLink"

const CHECKSUM_SPACES = 256

const OCTAL_SIZE_LIMIT = 0x1_FFFF_FFFFi
const BASE256_GUARD = 0x0080_0000_0000_0000i

const TYPE_DIRECTORY = 0x35
const TYPE_CONTIGUOUS = 0x37
const TYPE_LONG_LINK = 0x4B
const TYPE_LONG_NAME = 0x4C
const TYPE_FILE = 0x30

const FILE_MODE = 420
const DIRECTORY_MODE = 493

const LANE_HIGH = 0x8080_8080
const LANE_LOW = 0x0101_0101
const LANE_BYTES = 0x00FF_00FF

type ArchiveEntry = {
	Data: buffer,
	NameData: buffer,
	NameSum: number,
	LongData: buffer?,
	Directory: boolean,
	Size64: integer,
	Size: number,
}

const OCTAL_PAIRS = buffer.fromstring("\48\48\48\49\48\50\48\51\48\52\48\53\48\54\48\55\49\48\49\49\49\50\49\51\49\52\49\53\49\54\49\55\50\48\50\49\50\50\50\51\50\52\50\53\50\54\50\55\51\48\51\49\51\50\51\51\51\52\51\53\51\54\51\55\52\48\52\49\52\50\52\51\52\52\52\53\52\54\52\55\53\48\53\49\53\50\53\51\53\52\53\53\53\54\53\55\54\48\54\49\54\50\54\51\54\52\54\53\54\54\54\55\55\48\55\49\55\50\55\51\55\52\55\53\55\54\55\55")

@[native, checked] const function WriteOctal(Output: buffer, Offset: number, Value: number, Digits: number, Label: string): number
	local Remaining = Value
	local Total = 0
	local Position = Offset + Digits

	for _ = 1, Digits // 2 do
		const Pair = Remaining % 64
		Remaining //= 64
		Position -= 2
		buffer.writeu16(Output, Position, buffer.readu16(OCTAL_PAIRS, Pair * 2))
		Total += 0x60 + Pair // 8 + Pair % 8
	end
	if Digits % 2 == 1 then
		buffer.writeu8(Output, Offset, 0x30 + Remaining % 8)
		Total += 0x30 + Remaining % 8
		Remaining //= 8
	end
	if Remaining ~= 0 then
		error(`TAR64 {Label} is out of range`)
	end
	return Total
end

@[native, checked] const function WriteBase256(Output: buffer, Offset: number, Value: integer, Width: number, Label: string): number
	local Remaining = Value
	local Total = 0
	for Position = Offset + Width - 1, Offset + 1, -1 do
		const Byte = integer.tonumber(integer.urem(Remaining, 256i))
		buffer.writeu8(Output, Position, Byte)
		Total += Byte
		Remaining = integer.udiv(Remaining, 256i)
	end
	if integer.ugt(Remaining, 127i) then
		error(`TAR64 {Label} cannot be represented exactly`)
	end
	buffer.writeu8(Output, Offset, 0x80 + integer.tonumber(Remaining))
	Total += 0x80 + integer.tonumber(Remaining)
	return Total
end

@[native, checked] const function WriteNumeric(Output: buffer, Offset: number, Value: integer, Width: number, Digits: number, Label: string): number
	if integer.ule(Value, OCTAL_SIZE_LIMIT) then
		return WriteOctal(Output, Offset, integer.tonumber(Value), Digits, Label)
	end
	return WriteBase256(Output, Offset, Value, Width, Label)
end

@[native, checked] const function ChecksumRange(Data: buffer, Offset: number, Length: number): number
	local Even = 0
	local Odd = 0
	for Position = Offset, Offset + Length - 4, 4 do
		const Word = buffer.readu32(Data, Position)
		Even += bit32.band(Word, LANE_BYTES)
		Odd += bit32.band(bit32.rshift(Word, 8), LANE_BYTES)
	end
	return bit32.band(Even, 0xFFFF) + bit32.rshift(Even, 16) + bit32.band(Odd, 0xFFFF) + bit32.rshift(Odd, 16)
end

@[native, checked] const function HeaderChecksum(Data: buffer, Offset: number): number
	return ChecksumRange(Data, Offset, CHECKSUM_OFFSET) + CHECKSUM_SPACES + ChecksumRange(Data, Offset + CHECKSUM_OFFSET + CHECKSUM_LENGTH, HEADER_SIZE - CHECKSUM_OFFSET - CHECKSUM_LENGTH)
end

@[native, checked] const function ChecksumAndBytes(Data: buffer, Offset: number): (number, number)
	local Even = 0
	local Odd = 0
	local Any = 0
	for P = Offset + 16, Offset + CHECKSUM_OFFSET, 16 do
		const W1 = buffer.readu32(Data, P - 16)
		const W2 = buffer.readu32(Data, P - 12)
		const W3 = buffer.readu32(Data, P - 8)
		const W4 = buffer.readu32(Data, P - 4)
		Any = bit32.bor(Any, W1, W2, W3, W4)
		Even += bit32.band(W1, LANE_BYTES) + bit32.band(W2, LANE_BYTES) + bit32.band(W3, LANE_BYTES) + bit32.band(W4, LANE_BYTES)
		Odd += bit32.band(bit32.rshift(W1, 8), LANE_BYTES) + bit32.band(bit32.rshift(W2, 8), LANE_BYTES) + bit32.band(bit32.rshift(W3, 8), LANE_BYTES) + bit32.band(bit32.rshift(W4, 8), LANE_BYTES)
	end
	do
		const W = buffer.readu32(Data, Offset + CHECKSUM_OFFSET - 4)
		Any = bit32.bor(Any, W)
		Even += bit32.band(W, LANE_BYTES)
		Odd += bit32.band(bit32.rshift(W, 8), LANE_BYTES)
	end
	for P = Offset + CHECKSUM_OFFSET + CHECKSUM_LENGTH + 16, Offset + HEADER_SIZE, 16 do
		const W1 = buffer.readu32(Data, P - 16)
		const W2 = buffer.readu32(Data, P - 12)
		const W3 = buffer.readu32(Data, P - 8)
		const W4 = buffer.readu32(Data, P - 4)
		Any = bit32.bor(Any, W1, W2, W3, W4)
		Even += bit32.band(W1, LANE_BYTES) + bit32.band(W2, LANE_BYTES) + bit32.band(W3, LANE_BYTES) + bit32.band(W4, LANE_BYTES)
		Odd += bit32.band(bit32.rshift(W1, 8), LANE_BYTES) + bit32.band(bit32.rshift(W2, 8), LANE_BYTES) + bit32.band(bit32.rshift(W3, 8), LANE_BYTES) + bit32.band(bit32.rshift(W4, 8), LANE_BYTES)
	end
	do
		const W = buffer.readu32(Data, Offset + HEADER_SIZE - 4)
		Any = bit32.bor(Any, W)
		Even += bit32.band(W, LANE_BYTES)
		Odd += bit32.band(bit32.rshift(W, 8), LANE_BYTES)
	end
	return bit32.band(Even, 0xFFFF) + bit32.rshift(Even, 16) + bit32.band(Odd, 0xFFFF) + bit32.rshift(Odd, 16) + CHECKSUM_SPACES, Any
end

@[native, checked] const function NumberToInteger(Value: number, Label: string): integer
	if Value < 0 or Value ~= math.floor(Value) then
		error(`Invalid TAR64 {Label}`)
	end

	const Result = integer.create(Value)
	if Result == nil then
		error(`TAR64 {Label} cannot be represented exactly`)
	end
	return Result
end

@[native, checked] const function IntegerToNumber(Value: integer, Label: string): number
	const Result = integer.tonumber(Value)
	const RoundTrip = integer.create(Result)
	if RoundTrip == nil or RoundTrip ~= Value then
		error(`TAR64 {Label} cannot be represented exactly`)
	end
	return Result
end

@[native, checked] const function ScanName(NameData: buffer): (number, boolean)
	const Length = buffer.len(NameData)
	local Even = 0
	local Odd = 0
	local HasZero = false

	local Position = 0
	while Position + 4 <= Length do
		const Word = buffer.readu32(NameData, Position)
		if bit32.band(Word - LANE_LOW, bit32.band(bit32.bnot(Word), LANE_HIGH)) ~= 0 then
			HasZero = true
		end
		Even += bit32.band(Word, LANE_BYTES)
		Odd += bit32.band(bit32.rshift(Word, 8), LANE_BYTES)
		Position += 4
	end
	while Position < Length do
		const Byte = buffer.readu8(NameData, Position)
		if Byte == 0 then
			HasZero = true
		end
		Even += Byte
		Position += 1
	end
	return bit32.band(Even, 0xFFFF) + bit32.rshift(Even, 16) + bit32.band(Odd, 0xFFFF) + bit32.rshift(Odd, 16), HasZero
end

@[native, checked] const function ScanLength(Data: buffer, Offset: number, Limit: number): number
	local Position = 0
	while Position + 4 <= Limit do
		const Word = buffer.readu32(Data, Offset + Position)
		if bit32.band(Word - LANE_LOW, bit32.band(bit32.bnot(Word), LANE_HIGH)) ~= 0 then
			if bit32.band(Word, 0xFF) == 0 then
				return Position
			elseif bit32.band(Word, 0xFF00) == 0 then
				return Position + 1
			elseif bit32.band(Word, 0xFF0_000) == 0 then
				return Position + 2
			end
			return Position + 3
		end
		Position += 4
	end
	while Position < Limit do
		if buffer.readu8(Data, Offset + Position) == 0 then
			break
		end
		Position += 1
	end
	return Position
end

@[native, checked] const function DigitsValid(Word: number): boolean
	const Transformed = bit32.bxor(Word, 0x3030_3030)
	return bit32.band(bit32.bor(Transformed + 0x7878_7878, Transformed), LANE_HIGH) == 0
end

@[native, checked] const function ParseOctal8(Data: buffer, Offset: number, Label: string): number
	const Low = buffer.readu32(Data, Offset)
	const High = buffer.readu32(Data, Offset + 4)

	if DigitsValid(Low) and bit32.band(High, 0xFFFF_0000) == 0x2000_0000 and DigitsValid(bit32.bor(bit32.band(High, 0xFFFF), 0x3030_0000)) then
		return (bit32.lshift(bit32.band(Low, 0xFF), 15) + bit32.lshift(bit32.band(Low, 0xFF00), 4) + bit32.rshift(bit32.band(Low, 0xFF0_000), 7) + bit32.rshift(bit32.band(Low, 0xFF00_0000), 18)) + (bit32.lshift(bit32.band(High, 0xFF), 3) + bit32.rshift(bit32.band(High, 0xFF00), 8)) - 1_797_552
	end

	local Value = 0
	for Position = Offset, Offset + 7 do
		const Byte = buffer.readu8(Data, Position)
		if Byte >= 0x30 and Byte <= 0x37 then
			Value = (bit32.lshift(Value, 3)) + Byte - 0x30
		elseif Byte ~= 0 and Byte ~= 0x20 then
			error(`Invalid TAR64 {Label} field`)
		end
	end
	return Value
end

@[native, checked] const function ParseOctal12(Data: buffer, Offset: number, Label: string): number
	const Low = buffer.readu32(Data, Offset)
	const Middle = buffer.readu32(Data, Offset + 4)
	const High = buffer.readu32(Data, Offset + 8)

	const Terminator = bit32.rshift(High, 24)
	if (Terminator == 0 or Terminator == 0x20) and DigitsValid(Low) and DigitsValid(Middle) and DigitsValid(bit32.bor(bit32.band(High, 0x00FF_FFFF), 0x3000_0000)) then
		local Value = (bit32.band(Low, 0xFF) - 0x30) * 0x4000_0000 + bit32.lshift(bit32.band(Low, 0xFF00) - 0x3000, 19) + bit32.lshift(bit32.band(Low, 0xFF_0000) - 0x30_0000, 8) + bit32.rshift(bit32.band(Low, 0xFF00_0000) - 0x3000_0000, 3)
		Value += bit32.lshift(bit32.band(Middle, 0xFF) - 0x30, 18) + bit32.lshift(bit32.band(Middle, 0xFF00) - 0x3000, 7) + bit32.rshift(bit32.band(Middle, 0xFF_0000) - 0x30_0000, 4) + bit32.rshift(bit32.band(Middle, 0xFF00_0000) - 0x3000_0000, 15)
		Value += bit32.lshift(bit32.band(High, 0xFF) - 0x30, 6) + bit32.rshift(bit32.band(High, 0xFF00) - 0x3000, 5) + bit32.rshift(bit32.band(High, 0xFF_0000) - 0x30_0000, 16)
		return Value
	end

	local Value = 0
	for Position = Offset, Offset + 11 do
		const Byte = buffer.readu8(Data, Position)
		if Byte >= 0x30 and Byte <= 0x37 then
			Value = bit32.lshift(Value, 3) + Byte - 0x30
		elseif Byte ~= 0 and Byte ~= 0x20 then
			error(`Invalid TAR {Label} field`)
		end
	end
	return Value
end

@[native, checked] const function ParseNumeric(Data: buffer, Offset: number, Width: number, Label: string): integer
	if bit32.band(buffer.readu8(Data, Offset), 0x80) == 0 then
		return NumberToInteger(ParseOctal12(Data, Offset, Label), Label)
	end

	local Value = NumberToInteger(bit32.band(buffer.readu8(Data, Offset), 0x7F), Label)
	for Position = Offset + 1, Offset + Width - 1 do
		if integer.uge(Value, BASE256_GUARD) then
			error(`TAR64 {Label} cannot be represented exactly`)
		end
		Value = integer.add(integer.mul(Value, 256i), NumberToInteger(buffer.readu8(Data, Position), Label))
	end
	return Value
end

const TEMPLATE_FILE = buffer.create(HEADER_SIZE)
WriteOctal(TEMPLATE_FILE, MODE_OFFSET, FILE_MODE, MODE_DIGITS, "file mode")
WriteOctal(TEMPLATE_FILE, UID_OFFSET, 0, UID_DIGITS, "user id")
WriteOctal(TEMPLATE_FILE, GID_OFFSET, 0, GID_DIGITS, "group id")
WriteOctal(TEMPLATE_FILE, MTIME_OFFSET, 0, MTIME_DIGITS, "modification time")
buffer.fill(TEMPLATE_FILE, CHECKSUM_OFFSET, 0x20, CHECKSUM_LENGTH)
buffer.writeu8(TEMPLATE_FILE, TYPE_OFFSET, TYPE_FILE)
buffer.writestring(TEMPLATE_FILE, GNU_PREFIX_OFFSET, GNU_PREFIX, GNU_PREFIX_LENGTH)

const TEMPLATE_DIRECTORY = buffer.create(HEADER_SIZE)
buffer.copy(TEMPLATE_DIRECTORY, 0, TEMPLATE_FILE, 0, HEADER_SIZE)
WriteOctal(TEMPLATE_DIRECTORY, MODE_OFFSET, DIRECTORY_MODE, MODE_DIGITS, "file mode")
buffer.writeu8(TEMPLATE_DIRECTORY, TYPE_OFFSET, TYPE_DIRECTORY)

const TEMPLATE_LONG = buffer.create(HEADER_SIZE)
buffer.copy(TEMPLATE_LONG, 0, TEMPLATE_FILE, 0, HEADER_SIZE)
buffer.writestring(TEMPLATE_LONG, NAME_OFFSET, LONG_NAME)
buffer.writeu8(TEMPLATE_LONG, TYPE_OFFSET, TYPE_LONG_NAME)

const FILE_CHECKSUM = HeaderChecksum(TEMPLATE_FILE, 0)
const DIRECTORY_CHECKSUM = HeaderChecksum(TEMPLATE_DIRECTORY, 0)
const LONG_CHECKSUM = HeaderChecksum(TEMPLATE_LONG, 0)

@[native, checked] const function WriteHeader(Output: buffer, Position: number, Directory: boolean, NameData: buffer, NameSum: number, Size64: integer)
	const Template = if Directory then TEMPLATE_DIRECTORY else TEMPLATE_FILE
	buffer.copy(Output, Position, Template, 0, HEADER_SIZE)
	buffer.copy(Output, Position + NAME_OFFSET, NameData, 0, buffer.len(NameData))
	const HeaderSum = (if Directory then DIRECTORY_CHECKSUM else FILE_CHECKSUM) + NameSum + WriteNumeric(Output, Position + SIZE_OFFSET, Size64, SIZE_DIGITS + 1, SIZE_DIGITS, "entry size")
	WriteOctal(Output, Position + CHECKSUM_OFFSET, HeaderSum, CHECKSUM_DIGITS, "header checksum")
	buffer.writeu8(Output, Position + CHECKSUM_OFFSET + CHECKSUM_DIGITS, 0)
	buffer.writeu8(Output, Position + CHECKSUM_OFFSET + CHECKSUM_DIGITS + 1, 0x20)
end

@[native, checked] const function WriteLongHeader(Output: buffer, Position: number, Size64: integer)
	buffer.copy(Output, Position, TEMPLATE_LONG, 0, HEADER_SIZE)
	const HeaderSum = LONG_CHECKSUM + WriteOctal(Output, Position + SIZE_OFFSET, integer.tonumber(Size64), SIZE_DIGITS, "long name size")
	WriteOctal(Output, Position + CHECKSUM_OFFSET, HeaderSum, CHECKSUM_DIGITS, "header checksum")
	buffer.writeu8(Output, Position + CHECKSUM_OFFSET + CHECKSUM_DIGITS, 0)
	buffer.writeu8(Output, Position + CHECKSUM_OFFSET + CHECKSUM_DIGITS + 1, 0x20)
end

@[native, checked] const function Tar(Files: { [string]: buffer }): buffer
	const Names: { string } = {}
	for Name in Files do
		Names[#Names + 1] = Name
	end
	table.sort(Names)

	const Entries: { ArchiveEntry } = {}
	local TotalSize = 2 * BLOCK_SIZE

	for _, Name in Names do
		const Data = Files[Name]
		const FullName = buffer.fromstring(Name)
		const FullLength = buffer.len(FullName)
		if FullLength == 0 then
			error("TAR file name is empty")
		end

		const FullSum, HasZero = ScanName(FullName)
		if HasZero then
			error("TAR file name contains NUL")
		end

		local NameData = FullName
		local NameSum = FullSum
		local Long: buffer? = nil
		if FullLength > NAME_LENGTH then
			NameData = buffer.create(NAME_LENGTH)
			buffer.copy(NameData, 0, FullName, 0, NAME_LENGTH)
			NameSum = ScanName(NameData)
			Long = FullName
			TotalSize += HEADER_SIZE + bit32.band(FullLength + BLOCK_SIZE - 1, -BLOCK_SIZE)
		end

		const Size = buffer.len(Data)
		const Size64 = NumberToInteger(Size, "entry size")
		local Directory = false
		if buffer.readu8(FullName, FullLength - 1) == 0x2F then
			if Size ~= 0 then
				error(`TAR directory entry is not empty: {Name}`)
			end
			Directory = true
		end

		Entries[#Entries + 1] = {
			Data = Data,
			NameData = NameData,
			NameSum = NameSum,
			LongData = Long,
			Directory = Directory,
			Size64 = Size64,
			Size = Size,
		}
		TotalSize += HEADER_SIZE + bit32.band(Size + BLOCK_SIZE - 1, -BLOCK_SIZE)
	end

	NumberToInteger(TotalSize, "archive size")

	const Output = buffer.create(TotalSize)
	local Position = 0

	for _, Entry in Entries do
		if Entry.LongData ~= nil then
			const LongLength = buffer.len(Entry.LongData)
			WriteLongHeader(Output, Position, NumberToInteger(LongLength, "long name size"))
			buffer.copy(Output, Position + HEADER_SIZE, Entry.LongData, 0, LongLength)
			Position += HEADER_SIZE + bit32.band(LongLength + BLOCK_SIZE - 1, -BLOCK_SIZE)
		end

		WriteHeader(Output, Position, Entry.Directory, Entry.NameData, Entry.NameSum, Entry.Size64)
		Position += HEADER_SIZE
		if Entry.Size ~= 0 then
			buffer.copy(Output, Position, Entry.Data, 0, Entry.Size)
			Position += bit32.band(Entry.Size + BLOCK_SIZE - 1, -BLOCK_SIZE)
		end
	end

	return Output
end

@[native, checked] const function Untar(Data: buffer): { [string]: buffer }
	const Size = buffer.len(Data)
	if Size % BLOCK_SIZE ~= 0 then
		error("TAR file is truncated")
	end

	const Output: { [string]: buffer } = {}
	local Position = 0
	local PendingName: string?
	local PendingDirectory = false

	while Position + HEADER_SIZE <= Size do
		const ComputedChecksum, Any = ChecksumAndBytes(Data, Position)
		if Any == 0 then
			break
		end
		if buffer.readu32(Data, Position + GNU_PREFIX_OFFSET) ~= GNU_PREFIX_LOW or buffer.readu32(Data, Position + GNU_PREFIX_OFFSET + 4) ~= GNU_PREFIX_HIGH then
			error("Invalid TAR magic")
		end

		const NameLength = ScanLength(Data, Position + NAME_OFFSET, NAME_LENGTH)
		if NameLength == 0 then
			error("Invalid TAR entry name")
		end
		const StoredChecksum = ParseOctal8(Data, Position + CHECKSUM_OFFSET, "checksum")
		if StoredChecksum ~= ComputedChecksum then
			error(`TAR checksum mismatch: {buffer.readstring(Data, Position + NAME_OFFSET, NameLength)}`)
		end

		const EntrySize64 = ParseNumeric(Data, Position + SIZE_OFFSET, SIZE_DIGITS + 1, "entry size")
		const EntrySize = IntegerToNumber(EntrySize64, "entry size")
		const Type = buffer.readu8(Data, Position + TYPE_OFFSET)
		const DataStart = Position + HEADER_SIZE
		if DataStart + EntrySize > Size then
			error("TAR file data is truncated")
		end
		Position = DataStart + bit32.band(EntrySize + BLOCK_SIZE - 1, -BLOCK_SIZE)

		if Type == TYPE_LONG_NAME then
			local LongLength = EntrySize
			if LongLength > 0 and buffer.readu8(Data, DataStart + LongLength - 1) == 0 then
				LongLength -= 1
			end
			PendingName = if LongLength > 0 then buffer.readstring(Data, DataStart, LongLength) else ""
			PendingDirectory = LongLength > 0 and buffer.readu8(Data, DataStart + LongLength - 1) == 0x2F
			continue
		end
		if Type == TYPE_LONG_LINK then
			continue
		end

		local Name = buffer.readstring(Data, DataStart - HEADER_SIZE + NAME_OFFSET, NameLength)
		local DirectoryName = buffer.readu8(Data, DataStart - HEADER_SIZE + NAME_OFFSET + NameLength - 1) == 0x2F
		if PendingName ~= nil then
			Name = PendingName
			DirectoryName = PendingDirectory
			PendingName = nil
		end

		if Type == 0 or Type == TYPE_FILE or Type == TYPE_CONTIGUOUS then
			if DirectoryName then
				Output[Name] = buffer.create(0)
			else
				const Value = buffer.create(EntrySize)
				buffer.copy(Value, 0, Data, DataStart, EntrySize)
				Output[Name] = Value
			end
		elseif Type == TYPE_DIRECTORY then
			if DirectoryName then
				Output[Name] = buffer.create(0)
			else
				Output[`{Name}/`] = buffer.create(0)
			end
		else
			error(`Unsupported TAR entry type flag: {Type}`)
		end
	end

	return Output
end

return table.freeze({
	Tar = Tar,
	Untar = Untar,
})
