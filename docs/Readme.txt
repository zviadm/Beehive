Beehive v5.1

*** Building Hardware ***

-- To build hardware you will need Xilinx ISE (12.1)
-- Open ISE Project Navigator, File -> Open Project and choose 
   hwv51/RISC/risc.xise
-- After opening the project you need to set how many cores you want to have:
   (a) Set the nCores parameter in RiscTop.v,
   (b) Set the correct .bmm file by right clicking on "Implement Design" and
       selecting "Process Properties"
-- Right Click "Generate Programming File" and select "Rerun All"
-- After ISE is done building go to hwv51/ folder and type "make". It will
   automatically run correct scripts and make a correct .bit file.

*** Simulating Hardware ***

-- Open Project in ISE Project Navigator
-- Switch to "Simulation" view
-- Select one of the top level simulation modules and run
   "Simulate Behavioural Model"
-- To change the .img that simulation runs, go to sw/ and type:
   "make sim I=hello". (replace hello with your desired image name)
   
*** Building Software ***

-- Type "make" in sw/ folder
