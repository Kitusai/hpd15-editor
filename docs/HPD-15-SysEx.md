# Roland HPD-15 — SysEx reference (verified on hardware)

Source: HPD-15 Owner's Manual, MIDI Implementation (p. 97-109). Every point marked **verified** was checked on a real HPD-15 (UM-ONE interface, Device ID 17) in November 2026.

## Messages

- RQ1: `F0 41 dev 00 2E 11 aa bb cc dd ss tt uu vv sum F7` (16 bytes)
- DT1: `F0 41 dev 00 2E 12 aa bb cc dd data… sum F7`
- Model ID `00 2E` (**two** bytes). Device ID `00`-`1F` (1-32 on screen), factory `10` (17).
- Checksum: `(128 - (sum of address + data or size) % 128) & 7F`.
- Identity Reply: `F0 7E dev 06 02 41 2E 01 00 00 00 02 00 00 F7` — **verified**.
- Addresses and sizes are 7-bit (base 128).
- DT1: at most 128 data bytes per message, at least 40 ms between messages (manual).

## Timing — verified

**Any message (RQ1, DT1, Program Change) received less than ~30 ms after a reply from the HPD-15 is silently ignored.** Measured: 30 ms → 0/3 answered, 60 ms → 3/3. Wait at least 60 ms (100 ms recommended) after the last received byte before sending.

## Value encoding

- Fields whose size column reads `0000 aaaa` followed by `#` lines are **nibbled** (4 bits per byte, most significant first): instrument (4 bytes, 0-600), pitch (4 bytes, 0-4800, 2400 = 0 cent), pan (2 bytes, 1-129: 1 = L63, 64 = center, 127 = R63, 128 = random, 129 = alternate), MIDI note (2 bytes).
- Signed values −31…+31 are stored as 0-62 (31 = 0).
- Addresses marked `#` cannot be start addresses: write the whole nibbled value.

## Address map

| Address | Block |
|---|---|
| `00 00 00 00` | System (individual parameters) |
| `01 00 00 00` | **Temporary patch** (individual) — target of live edits |
| `10 00 00 00` | System (bulk) |
| `11 00 00 00` | Temporary patch (bulk) |
| `12 mm 00 00` | User patch U0101…U1008 (mm = `00`-`4F`) |
| `20 00 00 00` | User patterns (bulk) |

### Dump requests — verified

| Address | Size | Result |
|---|---|---|
| `11 00 00 00` | `01 00 00 00` | temporary patch: 27 DT1 at `11 00 xx 00` (one per sub-block, same offsets as `01 00 …`), ~70 ms apart, 992 bytes |
| `12 mm 00 00` | `00 01 00 00` | one user patch, same format at `12 mm xx 00` |

Size `00 00 00 00` returns nothing for patches. Preset patches cannot be dumped: select them by Bank Select + Program Change, wait ~1 s, then dump the temporary patch. Individual RQ1 on `01 00 xx 00` with the exact block size also works.

### System (offsets under `00 00 00 00`)

- `02 00 xx` MIDI: 00 Melo1 ch · 01 Melo2 · 02 Perc1 · 03 Perc2 · **04 Pad channel** (0-15, 16 = OFF) · 05 Local Control · 06 Soft Thru.
- Also: utility, foot switches, controllers, pad sensitivity (`04 pp xx`), triggers, patch chains.

### Patch (temporary `01 00 …` or user)

| Offset | Block | Size |
|---|---|---|
| `00 00` / `01 00` / `02 00` | Pad Set A / B / C | 0x0C |
| `10 00`…`1E 00` | Pads A1-A5 (`10`-`14`), B1-B5 (`15`-`19`), C1-C5 (`1A`-`1E`) | 0x2B |
| `1F 00` | Pedal | 0x2B |
| `20 00` | D Beam | 0x2B |
| `21 00` / `22 00` | Ribbon L / R | 0x2B |
| `23 00` / `24 00` | Trig 1 / 2 | 0x2B |
| `30 00` | Effect (reverb + multi-effect of the patch) | 0x18 |
| `38 00` | LFO | 0x08 |
| `40 00` | Common | 0x15 |

**Pad / trigger block (0x2B)**: 00-03 instrument (0-600) · 04-07 pitch · 08 level · 09-0A pan · 0B decay · 0C sweep · 0D color · 0E reverb send · 0F M-FX switch (pad routed to the multi-effect) · 10 trigger mode · 11 velocity curve · 12 roll Rx · 1B-21 control/MIDI options · 23-24 MIDI note · 25 gate time · 26-2A pad pattern (B1-C5).

**Pad Set block (0x0C)**: 00-01 instrument (Pad Set list) · 02-05 pitch (5-cent steps) · 06 level · 07-08 pan · 09 decay · 0A reverb send · 0B M-FX switch (OFF / ON / PadData).

**Effect block (0x18)**: 00 reverb type · 02 reverb algorithm · 03 level · 04 time · 05 HF damp · 06 delay feedback · 07 M-FX type · 08 M-FX depth · 09 M-FX algorithm · 0A output level · 0B reverb send · 0C-17 M-FX parameters 1-12.

**Common block (0x15)**: 00 master volume · 01 resonance limit · 02-07 D Beam / ribbons sound & hold · **08 MULTI EFFECTS on/off** · 09 pad sensitivity type · 0A roll speed · 0B-14 patch name (10 ASCII characters).

## Verified behaviours

- **Instrument numbers**: value = position in the instrument list, 0 = L01, 600 = Off.
- **Pad Set instrument**: value = number in the Pad Set list, 0 = none. **Writing it applies the five sounds of the set to the whole row**, and the HPD-15 recomputes it when a pad of the row is changed. Do not send it when restoring a patch.
- **MIDI note** of a pad (23-24): the stored value is the MIDI note number. Pads send Note On on the pad channel with that note.
- **Ribbons** send their note in one direction of the gesture and *note − 3* in the other (e.g. 59/56 and 78/75). D Beam sends its note.
- Pads A1 and A5 also send CC 16 / CC 17 (positional sensing).
- **Reverb type**: stored value = list position + 1 (1 = OFF, 2 = WarmRoom, 3 = DarkRoom…); 0 also behaves as OFF.
- **Multi-effect type**: stored value = list position + 1 (80 = Hall A, 74 = 4TempoDly, 36 = Stereo Cho).
- Writing only the type byte (reverb `00`, multi-effect `07`) is enough: the HPD-15 reconfigures the effect (algorithm and parameters).
- **Common 08 (MULTI EFFECTS)** decides everything: when off, no multi-effect is heard, even on pads routed to it.
- Writing DT1 to the temporary patch is heard immediately and can be read back.

## Patch selection

- On the pad channel. Bank Select MSB `00` = user (PC 0-79 = U0101…U1008), `01` = presets bank 2 (PC 0-127), `02` = presets bank 3 (PC 0-31). LSB is ignored.
- The HPD-15 sends Bank Select + Program Change when a patch is selected on the instrument; with Soft Thru ON it also echoes incoming messages.
- Presets cannot be written: [WRITE] only accepts user destinations.
