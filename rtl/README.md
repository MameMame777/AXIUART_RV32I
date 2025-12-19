# AXIUART RTL Design Specification

## Overview

This directory contains the complete RTL implementation of the AXIUART project - a UART-to-AXI4-Lite bridge that enables register access over a standard UART interface. The design provides a reliable communication path between a host system and AXI4-Lite memory-mapped peripherals using a custom protocol with CRC error detection.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Protocol Specification](#protocol-specification)
3. [Module Descriptions](#module-descriptions)
4. [Interface Definitions](#interface-definitions)
5. [Design Parameters](#design-parameters)
6. [Timing and Performance](#timing-and-performance)
7. [Error Handling](#error-handling)
8. [Reset Behavior](#reset-behavior)

## Register Management

### Centralized Register Definitions

The AXIUART project uses a **JSON-based Single Source of Truth** approach for register management:

**Source:** `register_map/axiuart_registers.json`

**Generated Outputs:**
1. **SystemVerilog Package** (`rtl/register_block/axiuart_reg_pkg.sv`)
   - Parameter definitions for all registers
   - Imported by `Register_Block.sv` and UVM testbench
   - Ensures address consistency across RTL and verification

2. **Python Constants** (`software/axiuart_driver/registers.py`)
   - Used by Python driver and control applications
   - Guarantees software-hardware address alignment

3. **Markdown Documentation** (`software/axiuart_driver/REGISTER_MAP.md`)
   - Human-readable reference with complete register details

**RTL Usage Example:**
```systemverilog
// rtl/register_block/Register_Block.sv
import axiuart_reg_pkg::*;  // Import generated package

// Use generated constants (absolute addresses)
localparam bit [11:0] REG_CONTROL = (axiuart_reg_pkg::REG_CONTROL - BASE_ADDR);
localparam bit [11:0] REG_STATUS  = (axiuart_reg_pkg::REG_STATUS - BASE_ADDR);
// ... rest computed automatically
```

**Regeneration Command:**
```bash
python software/axiuart_driver/tools/gen_registers.py \
  --in register_map/axiuart_registers.json
```

**Validation Rules:**
- All addresses must be 32-bit aligned
- No duplicate offsets allowed
- Deterministic ordering (sorted by offset)
- Automatic sanity checks on every generation

## Architecture Overview

### System Block Diagram

```
Host UART ──> UART RX ──> RX FIFO ──> Frame Parser ──> AXI4-Lite Master ──> Register Block
                                          │                      │
Host UART <── UART TX <── TX FIFO <── Frame Builder <─────────────┘
```

### Directory Structure

```
rtl/
├── uart_axi4_bridge/       # Reusable UART-AXI4 bridge core
│   ├── Uart_Axi4_Bridge.sv        # Top-level bridge controller
│   ├── Uart_Rx.sv                 # UART receiver with oversampling
│   ├── Uart_Tx.sv                 # UART transmitter
│   ├── Frame_Parser.sv            # Protocol frame parser (Host→Device)
│   ├── Frame_Builder.sv           # Protocol frame builder (Device→Host)
│   ├── Axi4_Lite_Master.sv        # AXI4-Lite master state machine
│   ├── Crc8_Calculator.sv         # CRC-8 checksum calculator
│   ├── Address_Aligner.sv         # AXI address alignment logic
│   └── fifo_sync.sv               # Synchronous FIFO implementation
│
├── register_block/         # Project-specific register implementation
│   └── Register_Block.sv          # Memory-mapped register file
│
├── interfaces/             # SystemVerilog interface definitions
│   ├── uart_if.sv                 # UART interface signals
│   ├── axi4_lite_if.sv            # Parameterized AXI4-Lite interface
│   └── bridge_status_if.sv        # Bridge status monitoring signals
│
├── AXIUART_Top.sv          # Top-level integration module
└── README.md               # This file
```

### Design Philosophy

1. **Modularity**: Bridge core is completely independent of register implementation
2. **Reusability**: UART-AXI4 bridge can be used in other projects without modification
3. **Parameterization**: Key design parameters are configurable at elaboration time
4. **Error Resilience**: Comprehensive error detection and reporting at all protocol layers
5. **Performance**: Optimized for 115200 baud UART operation with minimal AXI latency

## Protocol Specification

### Protocol Overview

The AXIUART protocol is a byte-oriented, frame-based communication protocol with the following key features:

- Start-of-Frame (SOF) markers for synchronization
- CRC-8 error detection on all frames
- Support for burst read/write operations (1-16 beats)
- Configurable transfer sizes (8-bit, 16-bit, 32-bit)
- Address auto-increment for sequential accesses
- Comprehensive error status reporting

**Complete protocol specification**: See `../docs/axiuart_bus_protocol.md`

### Frame Formats

#### Host to Device Command Frame

```
┌──────┬──────┬──────────────┬──────────────────────┬──────┐
│ SOF  │ CMD  │ ADDR (4B)    │ DATA (0-64B)         │ CRC  │
├──────┼──────┼──────────────┼──────────────────────┼──────┤
│ 0xA5 │ 1B   │ Little-endian│ Optional (writes only)│ 1B   │
└──────┴──────┴──────────────┴──────────────────────┴──────┘
```

**Command Byte Format (CMD[7:0])**:
```
┌───┬───┬─────────┬─────────────┐
│ 7 │ 6 │  5:4    │    3:0      │
├───┼───┼─────────┼─────────────┤
│RW │INC│ SIZE    │    LEN      │
└───┴───┴─────────┴─────────────┘

RW:   0 = Write, 1 = Read
INC:  0 = Fixed address, 1 = Auto-increment
SIZE: 00 = 8-bit, 01 = 16-bit, 10 = 32-bit, 11 = Reserved
LEN:  Beat count minus 1 (0-15, representing 1-16 beats)
```

**Special Commands**:
- **RESET Command**: `CMD = 0xFF`
  - Frame: `SOF (0xA5) | CMD (0xFF) | CRC (0x58)`
  - Performs soft reset of state machines and FIFOs
  - Preserves configuration registers (baud rate, timeout)
  - Returns standard ACK: `SOF (0x5A) | STATUS (0x00) | CMD (0xFF) | CRC (0x55)`

#### Device to Host Response Frames

**Write Acknowledgement**:
```
┌──────┬────────┬───────────┬──────┐
│ SOF  │ STATUS │ CMD echo  │ CRC  │
├──────┼────────┼───────────┼──────┤
│ 0x5A │ 1B     │ 1B        │ 1B   │
└──────┴────────┴───────────┴──────┘
```

**Read Response**:
```
┌──────┬────────┬───────────┬──────────────┬──────────────────────┬──────┐
│ SOF  │ STATUS │ CMD echo  │ ADDR (4B)    │ DATA (0-64B)         │ CRC  │
├──────┼────────┼───────────┼──────────────┼──────────────────────┼──────┤
│ 0x5A │ 1B     │ 1B        │ Little-endian│ Present if STATUS=0x00│ 1B   │
└──────┴────────┴───────────┴──────────────┴──────────────────────┴──────┘
```

### Status Codes

| Code   | Meaning                          | Source Module        |
|--------|----------------------------------|----------------------|
| 0x00   | Success                          | All modules          |
| 0x01   | CRC mismatch                     | Frame_Parser         |
| 0x02   | Unsupported command (SIZE=11)    | Frame_Parser         |
| 0x03   | Address alignment violation      | Address_Aligner      |
| 0x04   | AXI timeout                      | Axi4_Lite_Master     |
| 0x05   | AXI slave error (SLVERR/DECERR)  | Axi4_Lite_Master     |
| 0x06   | Bridge busy                      | Uart_Axi4_Bridge     |
| 0x07   | Length field out of range        | Frame_Parser         |

### CRC-8 Calculation

**Polynomial**: x^8 + x^2 + x + 1 (0x07)  
**Initial Value**: 0x00  
**Algorithm**: Standard CRC-8-CCITT

**Host→Device CRC Coverage**: CMD + ADDR + DATA (excludes SOF)  
**Device→Host CRC Coverage**: STATUS + CMD echo + ADDR echo + DATA (excludes SOF)

**Implementation**: See `uart_axi4_bridge/Crc8_Calculator.sv`

## Module Descriptions

### Top Level Module

#### AXIUART_Top.sv

**Purpose**: Top-level integration module connecting UART bridge to register block

**Key Features**:
- Instantiates UART-AXI4 bridge and register block
- Connects internal AXI4-Lite bus
- Provides system-level status monitoring
- Handles flow control signals (RTS/CTS)

**Parameters**:
```systemverilog
parameter int CLK_FREQ_HZ = 125_000_000    // System clock frequency
parameter int BAUD_RATE = 115200           // Fixed UART baud rate
parameter int AXI_TIMEOUT = 2500           // AXI timeout (20μs @ 125MHz)
parameter int RX_FIFO_DEPTH = 64           // RX FIFO depth
parameter int TX_FIFO_DEPTH = 64           // TX FIFO depth
parameter int REG_BASE_ADDR = 32'h00001000 // Register base address
```

**Interfaces**:
- **UART Physical**: `uart_rx`, `uart_tx`, `uart_rts_n`, `uart_cts_n`
- **Clock/Reset**: `clk`, `rst`
- **Debug**: `led`, optional simulation status outputs

### UART-AXI4 Bridge Core

#### Uart_Axi4_Bridge.sv

**Purpose**: Top-level controller coordinating all bridge operations

**Architecture**:
```
Main State Machine States:
- IDLE:           Waiting for new frame from parser
- WAIT_AXI:       AXI transaction in progress
- BUILD_RESPONSE: Constructing response frame
- ERROR_STATE:    Handling error conditions
```

**Key Responsibilities**:
1. Coordinate Frame Parser, AXI Master, and Frame Builder
2. Manage state transitions between parsing, AXI access, and response building
3. Handle soft reset requests from RESET command
4. Monitor system health (timeouts, busy conditions)
5. Provide debug instrumentation outputs

**Internal Signals**:
- `parser_frame_valid`: Indicates complete frame received
- `parser_frame_error`: Frame parsing error detected
- `axi_transaction_done`: AXI access completed
- `builder_response_complete`: Response frame sent

**Timing Behavior**:
- Frame parsing: Variable (depends on frame length)
- AXI transaction: 1-N cycles (depends on slave response)
- Response building: Variable (depends on response type)
- Total latency: Typically 1-5ms for single register access @ 115200 baud

#### Frame_Parser.sv

**Purpose**: Parse incoming UART byte stream into structured command frames

**State Machine**:
```
IDLE → CMD → ADDR_BYTE0 → ADDR_BYTE1 → ADDR_BYTE2 → ADDR_BYTE3 → 
       [DATA_RX (if write)] → CRC_RX → VALIDATE → [IDLE or ERROR]
```

**Key Features**:
1. **SOF Detection**: Waits for 0xA5 to begin frame parsing
2. **Command Decoding**: Extracts RW, INC, SIZE, LEN fields
3. **Address Assembly**: Reconstructs 32-bit address from 4 bytes (little-endian)
4. **Data Collection**: Receives 0-64 data bytes based on command
5. **CRC Validation**: Computes expected CRC and compares with received CRC
6. **Error Detection**: Validates command legality, address alignment, data length

**Validation Rules**:
- SIZE field must not be 0b11 (reserved)
- LEN field must be 0-15 (1-16 beats)
- Address alignment: Must be aligned to SIZE (8/16/32-bit boundaries)
- Timeout monitoring: Detects stalled byte reception (optional)

**Special Handling**:
- **RESET Command (0xFF)**: Triggers soft reset without full frame validation
- **Timeout Recovery**: Aborts frame and returns to IDLE on byte timeout

**Outputs**:
```systemverilog
output logic [7:0]  cmd                 // Parsed command byte
output logic [31:0] addr                // Parsed address
output logic [7:0]  data_out [0:63]     // Parsed data bytes
output logic [6:0]  data_count          // Number of valid data bytes
output logic        frame_valid         // Frame successfully parsed
output logic [7:0]  error_status        // Error code if frame_error=1
output logic        frame_error         // Frame parsing failed
output logic        soft_reset_request  // RESET command detected (pulse)
```

#### Frame_Builder.sv

**Purpose**: Construct response frames for transmission to host

**State Machine**:
```
IDLE → SOF → STATUS → CMD → [ADDR_BYTE0-3] → [DATA] → CRC → DONE → INTER_FRAME_GAP → IDLE
```

**Frame Type Selection**:
- **Write ACK**: SOF + STATUS + CMD + CRC (4 bytes)
- **Read Response**: SOF + STATUS + CMD + ADDR + DATA + CRC (10+ bytes)

**Key Features**:
1. **Response Triggering**: Edge detector on `build_response` input
2. **CRC Calculation**: Incrementally computes CRC over response bytes
3. **TX FIFO Management**: Monitors FIFO full condition before writing
4. **Inter-Frame Gap**: Inserts delay between consecutive responses

**CRC Byte Order**:
- STATUS → CMD → ADDR[0:3] → DATA[0:N] → CRC
- CRC covers all bytes except SOF

**Timing**:
- Write ACK: 4 bytes @ 115200 baud = ~350μs
- Read response (1x32-bit): 10 bytes = ~870μs
- Read response (16x32-bit): 70 bytes = ~6.1ms

#### Uart_Rx.sv

**Purpose**: UART receiver with 16x oversampling

**Key Features**:
1. **Oversampling**: 16 samples per bit period for noise immunity
2. **Start Bit Detection**: Detects falling edge on RX line
3. **Data Sampling**: Samples at middle of bit period
4. **Stop Bit Validation**: Checks for proper stop bit
5. **FIFO Interface**: Writes received bytes to RX FIFO

**Configuration**:
- **Format**: 8 data bits, no parity, 1 stop bit (8N1)
- **Baud Rate**: Fixed 115200 bps
- **Sampling Point**: Center of bit period (8th sample of 16)

**Error Detection**:
- Framing error: Invalid stop bit
- Overrun error: RX FIFO full when byte received

#### Uart_Tx.sv

**Purpose**: UART transmitter

**Key Features**:
1. **Bit Timing**: Precise bit period generation using baud divisor
2. **Idle State**: TX line held high when inactive
3. **Frame Format**: Start bit (0) + 8 data bits + stop bit (1)
4. **FIFO Interface**: Reads bytes from TX FIFO when available

**Transmission Timing**:
- 1 byte @ 115200 baud = 10 bits / 115200 = ~87μs
- Bit period = CLK_FREQ_HZ / BAUD_RATE = 1085 clocks @ 125MHz

#### Axi4_Lite_Master.sv

**Purpose**: AXI4-Lite master state machine for register access

**Architecture**:
```
Write Path: IDLE → ADDR → DATA → RESP → DONE
Read Path:  IDLE → ADDR → DATA → DONE
```

**Key Features**:
1. **Address Phase**: Drives AWADDR/ARADDR with address handshake
2. **Write Data Phase**: Drives WDATA with byte lane strobes
3. **Response Handling**: Captures BRESP/RRESP and converts to status codes
4. **Timeout Monitoring**: Detects hung AXI transactions
5. **Burst Support**: Handles multi-beat transactions with address increment

**AXI4-Lite Protocol Compliance**:
- All channels use valid/ready handshaking
- Write address and write data channels can occur in any order
- Read address and read data channels are strictly ordered
- Response codes mapped to protocol status codes

**Byte Lane Generation**:
```systemverilog
// Example: 16-bit write to address 0x1002
AWADDR = 0x1000 (aligned to 4-byte boundary)
WDATA  = 16'hXXXX << 16  (shifted to [31:16])
WSTRB  = 4'b1100          (enables bytes [3:2])
```

**Timeout Handling**:
- Configurable timeout counter (default: 2500 cycles = 20μs @ 125MHz)
- Timeout triggers error response and state machine reset
- Partial transactions are aborted

#### Crc8_Calculator.sv

**Purpose**: Hardware CRC-8 calculator using polynomial 0x07

**Algorithm**:
```
CRC-8-CCITT polynomial: x^8 + x^2 + x + 1 (0x07)
Initial value: 0x00
```

**Operation**:
1. Assert `crc_reset` to initialize to 0x00
2. Assert `crc_enable` for each byte to process
3. Provide data on `data_in`
4. Read result from `crc_out` (updates each cycle when enabled)

**Timing**:
- Combinational calculation: Result available next cycle after enable
- Sequential accumulation: New CRC = f(previous CRC, new data byte)

**Implementation**:
- Lookup table based for optimal timing
- Fully pipelined for high-speed operation

#### Address_Aligner.sv

**Purpose**: Validate and align AXI addresses based on transfer size

**Alignment Rules**:
- **8-bit**: No alignment requirement (any address valid)
- **16-bit**: Address must be 2-byte aligned (addr[0] = 0)
- **32-bit**: Address must be 4-byte aligned (addr[1:0] = 0)

**Functionality**:
1. Check address alignment based on SIZE field
2. Generate aligned address for AXI master
3. Calculate byte lane offsets within 32-bit word
4. Report alignment violations as errors

**Example Alignments**:
```
Original: 0x00001002, SIZE=16-bit → Aligned: 0x00001002, Valid (even address)
Original: 0x00001003, SIZE=16-bit → Aligned: 0x00001002, INVALID (odd address)
Original: 0x00001001, SIZE=32-bit → Aligned: 0x00001000, INVALID (not 4-byte aligned)
```

#### fifo_sync.sv

**Purpose**: Parameterized synchronous FIFO for RX/TX buffering

**Features**:
1. **Parameterized Width/Depth**: Configurable data width and depth
2. **Full/Empty Flags**: Indicates FIFO status
3. **Count Output**: Current number of entries in FIFO
4. **Threshold Flags**: Configurable high/low watermarks
5. **Synchronous Operation**: Single clock domain (no CDC logic)

**Implementation**:
- Dual-port RAM with independent read/write pointers
- Gray code counters for pointer comparison
- Combinational flags for zero-delay status

**Instantiations**:
- **RX FIFO**: 64 entries x 8 bits (stores received UART bytes)
- **TX FIFO**: 128 entries x 8 bits (stores response bytes for transmission)

### Register Block

#### Register_Block.sv

**Purpose**: Project-specific memory-mapped register file

**Address Map**:
```
Base Address: 0x00001000

Offset    Register Name      Access  Description
--------  ----------------   ------  ------------------------------------
0x0000    VERSION            RO      Hardware version (0x00010000 = v1.0)
0x0004    STATUS             RO      Bridge status flags
0x0008    CONFIG             RW      Configuration register
0x000C    CONTROL            RW      Control register
0x0010    ERROR_COUNT        RW      Error counter (write to clear)
0x0014    TX_COUNT           RO      Transmitted frame count
0x0018    RX_COUNT           RO      Received frame count
0x001C    FIFO_STATUS        RO      FIFO occupancy and flags

0x0020    REG_TEST_0         RW      Test register 0
0x0024    REG_TEST_1         RW      Test register 1
0x0028    REG_TEST_2         RW      Test register 2
0x002C    REG_TEST_3         RW      Test register 3
0x0040    REG_TEST_4         RW      Test register 4

0x1000-   (User registers)   -       Application-specific registers
0x1FFF
```

**Register Details**:

**VERSION (0x0000) - Read Only**:
```
[31:16] Major version (0x0001)
[15:0]  Minor version (0x0000)
```

**STATUS (0x0004) - Read Only**:
```
[7]    Bridge busy
[6]    Parser busy
[5]    Builder busy
[4]    AXI transaction active
[3]    RX FIFO high threshold
[2]    RX FIFO full
[1]    TX FIFO high threshold
[0]    TX FIFO empty
```

**CONFIG (0x0008) - Read/Write**:
```
[31:16] Baud divisor (read-only, fixed at 1085 for 115200 baud)
[15:8]  AXI timeout (in units of 10μs)
[7:4]   Debug mode select
[3]     Enable parser timeout
[2]     Enable assertions
[1]     Reserved
[0]     Soft reset request
```

**AXI4-Lite Slave Interface**:
- Implements full AXI4-Lite protocol with ready/valid handshaking
- Single-cycle read latency for most registers
- Write response always returns OKAY
- Address decoding with 4-byte granularity

**Byte Lane Handling**:
- Supports unaligned accesses with proper byte lane masking
- WSTRB[3:0] controls which bytes are updated
- Reads always return full 32-bit value regardless of access size

## Interface Definitions

### uart_if.sv

**Purpose**: Encapsulate UART physical signals

```systemverilog
interface uart_if;
    logic clk;      // System clock
    logic rst;      // Synchronous reset
    logic rx;       // UART receive line
    logic tx;       // UART transmit line
    logic cts_n;    // Clear to Send (active low)
    logic rts_n;    // Request to Send (active low)
    
    modport master (
        input  clk, rst, rx, cts_n,
        output tx, rts_n
    );
    
    modport monitor (
        input clk, rst, rx, tx, cts_n, rts_n
    );
endinterface
```

### axi4_lite_if.sv

**Purpose**: Parameterized AXI4-Lite interface

**Parameters**:
- `ADDR_WIDTH`: Address bus width (default: 32)
- `DATA_WIDTH`: Data bus width (default: 32)

**Channels**:
1. **Write Address Channel**: AWADDR, AWVALID, AWREADY, AWPROT
2. **Write Data Channel**: WDATA, WSTRB, WVALID, WREADY
3. **Write Response Channel**: BRESP, BVALID, BREADY
4. **Read Address Channel**: ARADDR, ARVALID, ARREADY, ARPROT
5. **Read Data Channel**: RDATA, RRESP, RVALID, RREADY

**Modports**:
- `master`: Used by Axi4_Lite_Master
- `slave`: Used by Register_Block
- `monitor`: Used by verification components (optional)

### bridge_status_if.sv

**Purpose**: Status and debug signals from bridge (optional)

```systemverilog
interface bridge_status_if;
    logic        bridge_busy;
    logic [7:0]  error_code;
    logic [15:0] tx_count;
    logic [15:0] rx_count;
    logic [7:0]  fifo_status;
    
    // Debug signals
    logic [7:0]  parser_cmd;
    logic [7:0]  builder_status;
    logic [3:0]  parser_state;
    logic [3:0]  builder_state;
endinterface
```

## Design Parameters

### System-Level Parameters

| Parameter          | Default      | Range           | Description                          |
|--------------------|--------------|-----------------|--------------------------------------|
| CLK_FREQ_HZ        | 125_000_000  | 10M - 500M      | System clock frequency               |
| BAUD_RATE          | 115200       | Fixed           | UART baud rate (not configurable)    |
| AXI_TIMEOUT        | 2500         | 100 - 1M        | AXI timeout in clock cycles          |
| UART_OVERSAMPLE    | 16           | 8, 16           | UART oversampling ratio              |
| RX_FIFO_DEPTH      | 64           | 8 - 256         | RX FIFO depth (entries)              |
| TX_FIFO_DEPTH      | 128          | 8 - 256         | TX FIFO depth (entries)              |
| MAX_LEN            | 16           | 1 - 16          | Maximum burst length                 |
| REG_BASE_ADDR      | 0x00001000   | Any 4K boundary | Register block base address          |

### Timing Parameters

**Baud Rate Divisor Calculation**:
```
baud_divisor = CLK_FREQ_HZ / BAUD_RATE
             = 125,000,000 / 115,200
             = 1085 clocks per bit
```

**AXI Timeout**:
```
timeout_us = (AXI_TIMEOUT * 1000) / (CLK_FREQ_HZ / 1000)
           = (2500 * 1000) / (125,000,000 / 1000)
           = 20μs
```

**FIFO Depths**:
- **RX FIFO (64 entries)**: Can buffer ~5 maximum-length command frames
- **TX FIFO (128 entries)**: Can buffer 2 maximum-length read responses (70 bytes each)

## Timing and Performance

### UART Timing

**Bit Period**:
```
1 bit @ 115200 baud = 8.68μs
1 byte (10 bits with start/stop) = 86.8μs
```

**Maximum Frame Sizes**:
- **Write command (max)**: 70 bytes = 6.08ms
  - SOF + CMD + ADDR(4) + DATA(64) + CRC
- **Read command**: 6 bytes = 521μs
  - SOF + CMD + ADDR(4) + CRC
- **Write ACK**: 4 bytes = 347μs
  - SOF + STATUS + CMD + CRC
- **Read response (max)**: 70 bytes = 6.08ms
  - SOF + STATUS + CMD + ADDR(4) + DATA(64) + CRC

### AXI Timing

**Best Case (single register access)**:
- Address phase: 1 cycle (if slave ready)
- Data phase: 1 cycle (if slave ready)
- Total: 2 cycles = 16ns @ 125MHz

**Worst Case (with wait states)**:
- Address phase: 1 + N cycles (slave inserts wait states)
- Data phase: 1 + M cycles
- Timeout limit: 2500 cycles = 20μs

**Typical Register Access**:
- Register_Block has single-cycle read latency
- Total AXI transaction: 2-3 cycles = 16-24ns

### End-to-End Latency

**Single Register Write (32-bit)**:
```
1. UART RX reception:        ~521μs (6 bytes)
2. Frame parsing:             ~50ns (validated)
3. AXI write transaction:     ~20ns (2-3 cycles)
4. Response building:         ~100ns (pipeline)
5. UART TX transmission:      ~347μs (4 bytes)
----------------------------------------
Total:                        ~868μs
```

**Single Register Read (32-bit)**:
```
1. UART RX reception:        ~521μs (6 bytes)
2. Frame parsing:             ~50ns
3. AXI read transaction:      ~20ns
4. Response building:         ~150ns
5. UART TX transmission:      ~868μs (10 bytes)
----------------------------------------
Total:                        ~1.39ms
```

**Throughput Calculations**:

**Sequential Writes**:
```
Frame time = 868μs per write
Throughput = 1 / 868μs = ~1152 writes/second
Data rate = 1152 × 4 bytes = 4.6 KB/s
```

**Sequential Reads**:
```
Frame time = 1.39ms per read
Throughput = 1 / 1.39ms = ~719 reads/second
Data rate = 719 × 4 bytes = 2.9 KB/s
```

**Burst Transfers**:
```
16-beat write (64 bytes payload):
Frame time = 6.08ms + 347μs = 6.43ms
Throughput = 64 / 6.43ms = 9.95 KB/s

16-beat read (64 bytes payload):
Frame time = 521μs + 6.08ms = 6.60ms
Throughput = 64 / 6.60ms = 9.70 KB/s
```

## Error Handling

### Error Detection Layers

1. **UART Physical Layer**: Framing errors (handled by Uart_Rx)
2. **Protocol Layer**: CRC errors, invalid commands (Frame_Parser)
3. **Address Layer**: Alignment violations (Address_Aligner)
4. **AXI Layer**: Slave errors, timeouts (Axi4_Lite_Master)

### Error Response Behavior

**Frame Parser Errors**:
- Invalid SOF: Discarded, parser returns to IDLE
- CRC mismatch: STATUS = 0x01 returned to host
- Invalid command: STATUS = 0x02 returned
- Address misalignment: STATUS = 0x03 returned
- Invalid length: STATUS = 0x07 returned

**AXI Transaction Errors**:
- Timeout: STATUS = 0x04, partial transaction aborted
- SLVERR: STATUS = 0x05, error propagated to host
- DECERR: STATUS = 0x05, invalid address decoded

**Bridge-Level Errors**:
- FIFO overflow: rx_fifo_full flag asserted, RTS deasserted
- Bridge busy: STATUS = 0x06 if new command arrives before ready

### Error Recovery

**Automatic Recovery**:
- CRC errors: Frame discarded, parser returns to IDLE
- Timeouts: State machines reset, bridge returns to IDLE
- FIFO overflow: Hardware flow control prevents overflow

**Manual Recovery**:
- RESET command (0xFF): Soft reset all state machines
- Hard reset (rst signal): Complete system reset
- Register writes: Clear error counters, reset statistics

### Debug Support

**Debug Outputs**:
- State machine visibility: `debug_parser_state`, `debug_builder_state`
- Command tracking: `debug_parser_cmd`, `debug_builder_cmd_echo`
- Status monitoring: `debug_parser_status`, `debug_builder_status`
- Error classification: `debug_error_cause`

**Waveform Debugging**:
- All major internal signals are named for waveform inspection
- State machine states use enumerated types for readability
- Transaction boundaries marked with pulse signals

## Reset Behavior

### Hard Reset (rst signal)

**Effect**: Complete system initialization

**State After Reset**:
- All state machines: IDLE
- All FIFOs: Empty
- All counters: Zero
- All status flags: Cleared
- Configuration registers: Default values
- AXI interface: Idle state

**Duration**: Synchronous, 1 clock cycle

### Soft Reset (RESET command 0xFF)

**Effect**: Selective state machine reset, preserves configuration

**State After Soft Reset**:
- Parser state: IDLE
- Builder state: IDLE
- AXI master state: IDLE
- RX FIFO: Cleared
- TX FIFO: Cleared
- Frame counters: Preserved
- Configuration registers: Preserved (baud divisor, timeout)
- Error counters: Preserved

**Use Case**: Safe baud rate switching sequence
```
1. Write new baud divisor to CONFIG register
2. Send RESET command (0xFF)
3. Switch host to new baud rate
4. Resume communication
```

**Implementation**:
```systemverilog
// In Frame_Parser
if (cmd_reg == CMD_RESET) begin
    soft_reset_request <= 1'b1;  // Pulse to bridge
    frame_valid <= 1'b1;          // Signal frame complete
    error_status_reg <= STATUS_OK;
end

// In Uart_Axi4_Bridge
if (soft_reset_request) begin
    // Reset state machines
    main_state <= IDLE;
    // Clear FIFOs
    rx_fifo_reset <= 1'b1;
    tx_fifo_reset <= 1'b1;
    // Preserve configuration
    // (no action on baud_divisor, timeout config)
end
```

### Power-On Reset

**Sequence**:
1. External reset signal asserted (active high)
2. All registers cleared
3. FIFOs initialized
4. State machines enter IDLE
5. Configuration loaded from parameters
6. System ready for operation

**Initialization Time**: 2-3 clock cycles after reset deassertion

## Design Constraints

### Synthesis Constraints

**Clock Domain**:
- Single clock domain (clk)
- Frequency: 125 MHz (8ns period)
- Duty cycle: 50%

**Reset**:
- Synchronous reset (rst)
- Active high
- Minimum assertion: 2 clock cycles

**I/O Timing**:
- UART RX: Asynchronous input, synchronized internally
- UART TX: Synchronous output, registered
- AXI signals: Synchronous, meet AXI4-Lite timing requirements

### Physical Constraints

**FIFO Depth Requirements**:
- RX FIFO must accommodate at least 1 maximum frame (70 bytes)
- TX FIFO must accommodate at least 1 maximum response (70 bytes)
- Recommended RX depth: 64 entries (headroom for parser latency)
- Recommended TX depth: 128 entries (double-buffered responses)

**Resource Utilization** (Estimated for Xilinx 7-series):
- Slice LUTs: ~2500
- Slice Registers: ~1800
- Block RAM (36Kb): 0 (FIFOs use distributed RAM)
- DSP48s: 0

## Verification Strategy

### Simulation Testbenches

**Location**: `../sim/uvm/`

**Test Coverage**:
1. Protocol compliance tests
2. Error injection and recovery
3. Boundary condition testing
4. Performance benchmarking
5. AXI protocol compliance

**See Also**: `../sim/README.md`, `../sim/uvm/UVM_ARCHITECTURE.md`

### Hardware Testing

**Required Equipment**:
- FPGA development board (125 MHz clock)
- USB-UART adapter (115200 baud)
- Logic analyzer (optional, for debugging)

**Test Software**: Python driver in `../software/axiuart_driver/`

## References

### Design Documentation
- Protocol Specification: `../docs/axiuart_bus_protocol.md`
- UVM Testbench: `../sim/uvm/UVM_ARCHITECTURE.md`
- Development Diary: `../docs/diary_*.md`

### External Standards
- AXI4-Lite Specification: ARM IHI 0022E
- UART Standard: RS-232, 8N1 format
- CRC-8-CCITT: Polynomial 0x07

### Tool Documentation
- Altair DSim 2025.1: UVM 1.2 simulation
- Xilinx Vivado: FPGA synthesis and implementation

## Revision History

| Version | Date          | Author | Description                        |
|---------|---------------|--------|------------------------------------|
| 1.0     | Dec 14, 2025  | -      | Initial RTL documentation          |

---

**Note**: This document reflects the current RTL implementation. For protocol-level details, refer to `../docs/axiuart_bus_protocol.md`. For verification details, see `../sim/README.md`.
