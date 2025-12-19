# uvm-hello-world
Simple UVM Hello World example to be simulated with Altair® DSim™ tools.

To simulate with DSim Desktop:

1. Start VS Code with DSim Desktop extension
2. In VS Code Explorer, navigate to uvm-hello-world/altair
3. Right-click on *\uvm_hello_world.dpf* and select `DSim Desktop: Open Project`
4. Beside **LIBRARY CONFIGURATION**, click `Compile Project`
5. Under **SIMULATION CONFIGURATION**, click `Run` beside **Elab 1** to elab locally
6. Under **SIMULATION CONFIGURATION**, click `Run` beside **Sim 1** to sim locally
7. Under **SIMULATION CONFIGURATION**, click `Run in DSim Cloud` beside **Elab and Sim** to run in cloud

To simulate with DSim Cloud:

1. In shell, navigate to uvm-hello-world/
2. Initialize a workspace
3. Navigate to /altair
4. `.\cloud_interactive.ps1` for Windows PowerShell or `sh cloud_interactive.sh` for Linux / Mac

To simulate with DSim locally:

1. In shell, navigate to uvm-hello-world/altair
2. `.\dsim_local.ps1` for Windows PowerShell or `sh dsim_local.sh` for Linux / Mac
