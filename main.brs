'import "pkg:/source/Theme.bs"

'-------------------------------------------------------------------------------
' Main
'-------------------------------------------------------------------------------
sub Main(args = invalid as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    input = CreateObject("roInput")
    input.SetMessagePort(port)
    globalNode = screen.GetGlobalNode()
    globalNode.AddFields({
        resolutionProfile: ResolutionProfile_Create()
        theme: "blue"
        uiLanguage: I18n_ReadLanguage()
        reduceMotion: false
    })
    globalNode.AddField("logService", "node", false)
    globalNode.logService = CreateObject("roSGNode", "LogService")
    ' required for Roku app certification
    memoryMonitor = CreateObject("roAppMemoryMonitor")
    memoryMonitor.SetMessagePort(port)
    memoryEventsEnabled = memoryMonitor.EnableMemoryWarningEvent(true)
    print "memoryLimitPercent="; memoryMonitor.GetMemoryLimitPercent()
    print "channelAvailableMemoryKb="; memoryMonitor.GetChannelAvailableMemory()
    memoryLimit = memoryMonitor.GetChannelMemoryLimit()
    if memoryLimit <> invalid then
        print "maxForegroundMemory="; memoryLimit.maxForegroundMemory
        print "maxBackgroundMemory="; memoryLimit.maxBackgroundMemory
        print "maxRokuManagedHeapMemory="; memoryLimit.maxRokuManagedHeapMemory
    end if
    if memoryEventsEnabled <> true then
        deviceInfo = CreateObject("roDeviceInfo")
        deviceInfo.SetMessagePort(port)
        deviceInfo.EnableLowGeneralMemoryEvent(true)
    end if
    scene = screen.CreateScene("MainScene")
    screen.Show()
    if args <> invalid
        print "[STREMIO][DEEPLINK] coldLaunch type="; Type(args)
        if Type(args) = "roAssociativeArray"
            print "[STREMIO][DEEPLINK] coldLaunch contentId="; Format_SafeString(args.contentId, "")
            print "[STREMIO][DEEPLINK] coldLaunch mediaType="; Format_SafeString(args.mediaType, "")
        end if
    else
        print "[STREMIO][DEEPLINK] coldLaunch args=invalid"
    end if
    scene.callFunc("startApp", args)
    while true
        msg = wait(100, port)
        if scene.closeRequested = true then
            screen.Close()
            return
        end if
        if type(msg) = "roSGScreenEvent" then
            if msg.isScreenClosed() then
                return
            end if
        else if type(msg) = "roAppMemoryNotificationEvent" then
            info = msg.GetInfo()
            if info <> invalid then
                print "memoryUsagePercent="; info.Lookup("MemoryUsagePercent")
            end if
        else if type(msg) = "roDeviceInfoEvent" then
            info = msg.GetInfo()
            if info <> invalid and info.generalMemoryLevel <> invalid then
                print "generalMemoryLevel="; info.generalMemoryLevel
            end if
        else if type(msg) = "roInputEvent" then
            scene.callFunc("submitInput", msg.GetInfo(), false)
        end if
    end while
end sub
