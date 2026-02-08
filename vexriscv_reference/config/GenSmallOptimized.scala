package vexriscv.demo

import vexriscv._
import vexriscv.plugin._
import spinal.core._

/**
 * GenSmallOptimized - Custom VexRiscv configuration for AXIUART_RV32I
 * 
 * Key features:
 * - Exposed IBus/DBus interfaces (not internal)
 * - DebugPlugin with shared reset domain
 * - CsrPlugin with mcycle/minstret counters
 * - Reset vector at 0x80000000 (matches BRAM layout)
 * - bypassWriteBackBuffer = true (fixes WB->ID forwarding race)
 * 
 * Generated: 2026-02-06
 */
object GenSmallOptimized {
  def main(args: Array[String]): Unit = {
    val outputDir = if (args.length > 0) args(0) else "vexriscv_reference/generated"
    
    SpinalConfig(
      targetDirectory = outputDir,
      defaultConfigForClockDomains = ClockDomainConfig(resetKind = spinal.core.SYNC),
      onlyStdLogicVectorAtTopLevelIo = true
    ).generateVerilog {
      
      val config = VexRiscvConfig(
        plugins = List(
          // PC Management Plugin - Reset vector at 0x80000000 (BRAM base)
          new IBusSimplePlugin(
            resetVector = 0x80000000l,
            cmdForkOnSecondStage = false,
            cmdForkPersistence = false,
            prediction = NONE,
            catchAccessFault = false,
            compressedGen = false
          ),
          
          // Instruction Decoder
          new DecoderSimplePlugin(
            catchIllegalInstruction = false
          ),
          
          // Register File Plugin
          new RegFilePlugin(
            regFileReadyKind = plugin.SYNC,
            zeroBoot = false
          ),
          
          // Integer ALU
          new IntAluPlugin,
          
          // Source Operand Selection
          new SrcPlugin(
            separatedAddSub = false,
            executeInsertion = true
          ),
          
          // Shifter (light version for area optimization)
          new LightShifterPlugin,
          
          // *** CRITICAL: Hazard Detection with WB Buffer ***
          // bypassWriteBackBuffer = true fixes the WB->ID forwarding race
          // that causes intermittent failures in rv32i_wb_forward_timing_test
          new HazardSimplePlugin(
            bypassExecute = true,
            bypassMemory = true,
            bypassWriteBack = true,
            bypassWriteBackBuffer = true  // ← KEY OPTIMIZATION
          ),
          
          // Branch Plugin
          new BranchPlugin(
            earlyBranch = false,
            catchAddressMisaligned = false
          ),
          
          // Data Bus Plugin
          new DBusSimplePlugin(
            catchAddressMisaligned = false,
            catchAccessFault = false
          ),
          
          // CSR Plugin with performance counter access
          new CsrPlugin(
            CsrPluginConfig(
              catchIllegalAccess = false,
              mvendorid = null,
              marchid = null,
              mimpid = null,
              mhartid = null,
              misaExtensionsInit = 0,
              misaAccess = CsrAccess.NONE,
              mtvecAccess = CsrAccess.READ_WRITE,
              mtvecInit = 0x80000000l,
              mepcAccess = CsrAccess.READ_WRITE,
              mscratchGen = false,
              mcauseAccess = CsrAccess.READ_ONLY,
              mbadaddrAccess = CsrAccess.NONE,
              mcycleAccess = CsrAccess.READ_ONLY,
              minstretAccess = CsrAccess.READ_ONLY,
              ecallGen = true,
              ebreakGen = true,
              wfiGenAsWait = false,
              wfiGenAsNop = true,
              ucycleAccess = CsrAccess.READ_ONLY
            )
          ),
          
          // Debug Plugin - Shared reset domain (no separate debugReset)
          new DebugPlugin(
            debugClockDomain = ClockDomain.current,
            hardwareBreakpointCount = 2
          ),
          
          // YAML documentation generator
          new YamlPlugin(s"$outputDir/cpu.yaml")
        )
      )
      
      val cpu = new VexRiscv(config)
      // Note: IBus/DBus are NOT set as directionless - they will be exposed at top level
      cpu
    }
    
    println(s"VexRiscv GenSmallOptimized generated successfully in $outputDir/")
    println("Generated files:")
    println(s"  - $outputDir/VexRiscv.v")
    println(s"  - $outputDir/cpu.yaml")
    println("Exposed interfaces: IBus, DBus, Debug")
  }
}
