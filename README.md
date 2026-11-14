# Check the codes in netlists<br>
The codes haven't been verified with a testbench yet. I asked Claude fable to do a preliminary check, and it said it looks fine.<br>
`core.v`:Top module, ports are implemented the same as in the `core_tb.v`(provided in course github's `project` folder, not included here because it's used in part3)<br>
`sram_32b_w2048`:Sram with 2048 registers of 32 bits , I used it for storing activation and weight inputs<br>
`sram_32b_w2048`:Sram with 2048 registers of 128 bits , I used it for storing psum. Receive input from ofifo, send the psums to sfp, and again receive from sfp <br>
`corelet.v`:Functionality top module, bridge between sram(data storage) and processing units. The modeule to be sent to FPGA for simulation<br>
`l0.v`:A transposed ofifo, receive weight and activation from sram, arrange them in columns and send ordered columns into mac array<br>
`mac_array.v`:Main multi and add processing pipeline. Directly copied from hw6, no change<br>
`mac_row.v`:Directly copied from hw6, no change<br>
`mac_tile.v`:Directly copied from hw6, no change<br>
`mac.v`:Directly copied from hw6, no change<br>
`ofifo.v`:8 columns of fifo, receive calculated result from mac array and put them in order
`fifo_depth64.v`:Storage units in ofifo, 64 in total, each with 16 bits
`sfp.v`: Process accumulation and ReLU for raw psum and get final psum. Claude wrote this, sorry about that
`sram_2ports.v`: Might use later for psum sram to speedup the pipeline. Need modification if used
