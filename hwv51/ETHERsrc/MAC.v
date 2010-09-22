
module MAC
(

    // Client Receiver Interface
    output          RXclockOut,
    input           RXclockIn,
    output   [7:0]  RXdata,
    output          RXdataValid,
    output          RXgoodFrame,
    output          RXbadFrame,
    // Client Transmitter Interface
    input           TXclockIn,
    input    [7:0]  TXdata,
    input           TXdataValid,
    input           TXdataValidMSW,
    output          TXack,
    input           TXfirstByte,
    input           TXunderrun,

    // MAC Control Interface
    input           PauseRequest,
    input   [15:0]  PauseValue,

    // Clock Signals
    input           TXgmiiMiiClockIn,
	 input           MIItxClock,

    // GMII Interface
    output   [7:0]  GMIItxData,
    output          GMIItxEnable,
    output          GMIItxError,
    input    [7:0]  GMIIrxData,
    input           GMIIrxDataValid,
    input           GMIIrxClock,
    input           DCMlocked,
    // Asynchronous Reset
    input           Reset
	 );


    wire    [15:0]  RXmacData;
    wire    [15:0]  TXmacData;

    assign RXdata = RXmacData[7:0];  //TEMAC has a 16-bit interface
    assign TXmacData = {8'b00000000, TXdata};

    //--------------------------------------------------------------------------
    // Instantiate the Virtex-5 Embedded Ethernet EMAC
    //--------------------------------------------------------------------------
    TEMAC v5_emac
    (
        .RESET                          (Reset),

        // EMAC0
        .EMAC0CLIENTRXCLIENTCLKOUT      (RXclockOut),
        .CLIENTEMAC0RXCLIENTCLKIN       (RXclockIn),
        .EMAC0CLIENTRXD                 (RXmacData),
        .EMAC0CLIENTRXDVLD              (RXdataValid),
        .EMAC0CLIENTRXDVLDMSW           (),
        .EMAC0CLIENTRXGOODFRAME         (RXgoodFrame),
        .EMAC0CLIENTRXBADFRAME          (RXbadFrame),
        .EMAC0CLIENTRXFRAMEDROP         (),
        .EMAC0CLIENTRXSTATS             (),
        .EMAC0CLIENTRXSTATSVLD          (),
        .EMAC0CLIENTRXSTATSBYTEVLD      (),

        .EMAC0CLIENTTXCLIENTCLKOUT      (),
        .CLIENTEMAC0TXCLIENTCLKIN       (TXclockIn),
        .CLIENTEMAC0TXD                 (TXmacData),
        .CLIENTEMAC0TXDVLD              (TXdataValid),
        .CLIENTEMAC0TXDVLDMSW           (TXdataValidMSW),
        .EMAC0CLIENTTXACK               (TXack),
        .CLIENTEMAC0TXFIRSTBYTE         (TXfirstByte),
        .CLIENTEMAC0TXUNDERRUN          (TXunderrun),
        .EMAC0CLIENTTXCOLLISION         (),
        .EMAC0CLIENTTXRETRANSMIT        (),
        .CLIENTEMAC0TXIFGDELAY          (),
        .EMAC0CLIENTTXSTATS             (),
        .EMAC0CLIENTTXSTATSVLD          (),
        .EMAC0CLIENTTXSTATSBYTEVLD      (),

        .CLIENTEMAC0PAUSEREQ            (PauseRequest),
        .CLIENTEMAC0PAUSEVAL            (PauseValue),

        .PHYEMAC0GTXCLK                 (1'b0),
        .EMAC0PHYTXGMIIMIICLKOUT        (),
        .PHYEMAC0TXGMIIMIICLKIN         (TXgmiiMiiClockIn),

        .PHYEMAC0RXCLK                  (GMIIrxClock),
        .PHYEMAC0RXD                    (GMIIrxData),
        .PHYEMAC0RXDV                   (GMIIrxDataValid),
        .PHYEMAC0RXER                   (1'b0),
        .EMAC0PHYTXCLK                  (),
        .EMAC0PHYTXD                    (GMIItxData),
        .EMAC0PHYTXEN                   (GMIItxEnable),
        .EMAC0PHYTXER                   (GMIItxError),
        .PHYEMAC0MIITXCLK               (MIItxClock),
        .PHYEMAC0COL                    (1'b0),
        .PHYEMAC0CRS                    (1'b0),

        .CLIENTEMAC0DCMLOCKED           (DCMlocked),
        .EMAC0CLIENTANINTERRUPT         (),
        .PHYEMAC0SIGNALDET              (1'b0),
        .PHYEMAC0PHYAD                  (5'b00000),
        .EMAC0PHYENCOMMAALIGN           (),
        .EMAC0PHYLOOPBACKMSB            (),
        .EMAC0PHYMGTRXRESET             (),
        .EMAC0PHYMGTTXRESET             (),
        .EMAC0PHYPOWERDOWN              (),
        .EMAC0PHYSYNCACQSTATUS          (),
        .PHYEMAC0RXCLKCORCNT            (3'b000),
        .PHYEMAC0RXBUFSTATUS            (2'b00),
        .PHYEMAC0RXBUFERR               (1'b0),
        .PHYEMAC0RXCHARISCOMMA          (1'b0),
        .PHYEMAC0RXCHARISK              (1'b0),
        .PHYEMAC0RXCHECKINGCRC          (1'b0),
        .PHYEMAC0RXCOMMADET             (1'b0),
        .PHYEMAC0RXDISPERR              (1'b0),
        .PHYEMAC0RXLOSSOFSYNC           (2'b00),
        .PHYEMAC0RXNOTINTABLE           (1'b0),
        .PHYEMAC0RXRUNDISP              (1'b0),
        .PHYEMAC0TXBUFERR               (1'b0),
        .EMAC0PHYTXCHARDISPMODE         (),
        .EMAC0PHYTXCHARDISPVAL          (),
        .EMAC0PHYTXCHARISK              (),

        .EMAC0PHYMCLKOUT                (),
        .PHYEMAC0MCLKIN                 (1'b0),
        .PHYEMAC0MDIN                   (1'b1),
        .EMAC0PHYMDOUT                  (),
        .EMAC0PHYMDTRI                  (),
        .EMAC0SPEEDIS10100              (),

        // EMAC1
        .EMAC1CLIENTRXCLIENTCLKOUT      (),
        .CLIENTEMAC1RXCLIENTCLKIN       (1'b0),
        .EMAC1CLIENTRXD                 (),
        .EMAC1CLIENTRXDVLD              (),
        .EMAC1CLIENTRXDVLDMSW           (),
        .EMAC1CLIENTRXGOODFRAME         (),
        .EMAC1CLIENTRXBADFRAME          (),
        .EMAC1CLIENTRXFRAMEDROP         (),
        .EMAC1CLIENTRXSTATS             (),
        .EMAC1CLIENTRXSTATSVLD          (),
        .EMAC1CLIENTRXSTATSBYTEVLD      (),

        .EMAC1CLIENTTXCLIENTCLKOUT      (),
        .CLIENTEMAC1TXCLIENTCLKIN       (1'b0),
        .CLIENTEMAC1TXD                 (16'h0000),
        .CLIENTEMAC1TXDVLD              (1'b0),
        .CLIENTEMAC1TXDVLDMSW           (1'b0),
        .EMAC1CLIENTTXACK               (),
        .CLIENTEMAC1TXFIRSTBYTE         (1'b0),
        .CLIENTEMAC1TXUNDERRUN          (1'b0),
        .EMAC1CLIENTTXCOLLISION         (),
        .EMAC1CLIENTTXRETRANSMIT        (),
        .CLIENTEMAC1TXIFGDELAY          (8'h00),
        .EMAC1CLIENTTXSTATS             (),
        .EMAC1CLIENTTXSTATSVLD          (),
        .EMAC1CLIENTTXSTATSBYTEVLD      (),

        .CLIENTEMAC1PAUSEREQ            (1'b0),
        .CLIENTEMAC1PAUSEVAL            (16'h0000),

        .PHYEMAC1GTXCLK                 (1'b0),
        .EMAC1PHYTXGMIIMIICLKOUT        (),
        .PHYEMAC1TXGMIIMIICLKIN         (1'b0),

        .PHYEMAC1RXCLK                  (1'b0),
        .PHYEMAC1RXD                    (8'h00),
        .PHYEMAC1RXDV                   (1'b0),
        .PHYEMAC1RXER                   (1'b0),
        .PHYEMAC1MIITXCLK               (1'b0),
        .EMAC1PHYTXCLK                  (),
        .EMAC1PHYTXD                    (),
        .EMAC1PHYTXEN                   (),
        .EMAC1PHYTXER                   (),
        .PHYEMAC1COL                    (1'b0),
        .PHYEMAC1CRS                    (1'b0),

        .CLIENTEMAC1DCMLOCKED           (1'b1),
        .EMAC1CLIENTANINTERRUPT         (),
        .PHYEMAC1SIGNALDET              (1'b0),
        .PHYEMAC1PHYAD                  (5'b00000),
        .EMAC1PHYENCOMMAALIGN           (),
        .EMAC1PHYLOOPBACKMSB            (),
        .EMAC1PHYMGTRXRESET             (),
        .EMAC1PHYMGTTXRESET             (),
        .EMAC1PHYPOWERDOWN              (),
        .EMAC1PHYSYNCACQSTATUS          (),
        .PHYEMAC1RXCLKCORCNT            (3'b000),
        .PHYEMAC1RXBUFSTATUS            (2'b00),
        .PHYEMAC1RXBUFERR               (1'b0),
        .PHYEMAC1RXCHARISCOMMA          (1'b0),
        .PHYEMAC1RXCHARISK              (1'b0),
        .PHYEMAC1RXCHECKINGCRC          (1'b0),
        .PHYEMAC1RXCOMMADET             (1'b0),
        .PHYEMAC1RXDISPERR              (1'b0),
        .PHYEMAC1RXLOSSOFSYNC           (2'b00),
        .PHYEMAC1RXNOTINTABLE           (1'b0),
        .PHYEMAC1RXRUNDISP              (1'b0),
        .PHYEMAC1TXBUFERR               (1'b0),
        .EMAC1PHYTXCHARDISPMODE         (),
        .EMAC1PHYTXCHARDISPVAL          (),
        .EMAC1PHYTXCHARISK              (),

        .EMAC1PHYMCLKOUT                (),
        .PHYEMAC1MCLKIN                 (1'b0),
        .PHYEMAC1MDIN                   (1'b0),
        .EMAC1PHYMDOUT                  (),
        .EMAC1PHYMDTRI                  (),
        .EMAC1SPEEDIS10100              (),

        // Host Interface 
        .HOSTCLK                        (1'b0),
        .HOSTOPCODE                     (2'b00),
        .HOSTREQ                        (1'b0),
        .HOSTMIIMSEL                    (1'b0),
        .HOSTADDR                       (10'b0000000000),
        .HOSTWRDATA                     (32'h00000000),
        .HOSTMIIMRDY                    (),
        .HOSTRDDATA                     (),
        .HOSTEMAC1SEL                   (1'b0),

        // DCR Interface
        .DCREMACCLK                     (1'b0),
        .DCREMACABUS                    (10'h000),
        .DCREMACREAD                    (1'b0),
        .DCREMACWRITE                   (1'b0),
        .DCREMACDBUS                    (32'h00000000),
        .EMACDCRACK                     (),
        .EMACDCRDBUS                    (),
        .DCREMACENABLE                  (1'b0),
        .DCRHOSTDONEIR                  ()
    );
    defparam v5_emac.EMAC0_PHYINITAUTONEG_ENABLE = "FALSE";
    defparam v5_emac.EMAC0_PHYISOLATE = "FALSE";
    defparam v5_emac.EMAC0_PHYLOOPBACKMSB = "FALSE";
    defparam v5_emac.EMAC0_PHYPOWERDOWN = "FALSE";
    defparam v5_emac.EMAC0_PHYRESET = "TRUE";
    defparam v5_emac.EMAC0_CONFIGVEC_79 = "FALSE";
    defparam v5_emac.EMAC0_GTLOOPBACK = "FALSE";
    defparam v5_emac.EMAC0_UNIDIRECTION_ENABLE = "FALSE";
    defparam v5_emac.EMAC0_LINKTIMERVAL = 9'h000;
    defparam v5_emac.EMAC0_MDIO_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_SPEED_LSB = "FALSE";
    defparam v5_emac.EMAC0_SPEED_MSB = "TRUE"; 
    defparam v5_emac.EMAC0_USECLKEN = "FALSE";
    defparam v5_emac.EMAC0_BYTEPHY = "FALSE";
    defparam v5_emac.EMAC0_RGMII_ENABLE = "FALSE";
    defparam v5_emac.EMAC0_SGMII_ENABLE = "FALSE";
    defparam v5_emac.EMAC0_1000BASEX_ENABLE = "FALSE";
    defparam v5_emac.EMAC0_HOST_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_TX16BITCLIENT_ENABLE = "FALSE";
    defparam v5_emac.EMAC0_RX16BITCLIENT_ENABLE = "FALSE";    
    defparam v5_emac.EMAC0_ADDRFILTER_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_LTCHECK_DISABLE = "FALSE";  
    defparam v5_emac.EMAC0_RXFLOWCTRL_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_TXFLOWCTRL_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_TXRESET = "FALSE";  
    defparam v5_emac.EMAC0_TXJUMBOFRAME_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_TXINBANDFCS_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_TX_ENABLE = "TRUE";  
    defparam v5_emac.EMAC0_TXVLAN_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_TXHALFDUPLEX = "FALSE";  
    defparam v5_emac.EMAC0_TXIFGADJUST_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_RXRESET = "FALSE";  
    defparam v5_emac.EMAC0_RXJUMBOFRAME_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_RXINBANDFCS_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_RX_ENABLE = "TRUE";  
    defparam v5_emac.EMAC0_RXVLAN_ENABLE = "FALSE";  
    defparam v5_emac.EMAC0_RXHALFDUPLEX = "FALSE";  
    defparam v5_emac.EMAC0_PAUSEADDR = 48'hFFEEDDCCBBAA;
    defparam v5_emac.EMAC0_UNICASTADDR = 48'h000000000000;
    defparam v5_emac.EMAC0_DCRBASEADDR = 8'h00;

endmodule

