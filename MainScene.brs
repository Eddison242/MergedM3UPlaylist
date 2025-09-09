sub init()
    m.list = m.top.findNode("list")
    m.video = m.top.findNode("video")
    m.kbd = m.top.findNode("kbd")

    m.list.ObserveField("itemSelected", "onItemSelected")

    ' read default from manifest or fallback
    m.feedUrl = getFeedUrlFromManifest()
    if m.feedUrl = invalid or m.feedUrl = ""
        m.feedUrl = "http://m3u4u.com/m3u/4z2xnjk284a2qek9yv15"
    end if

    ' kick off initial load
    loadChannels(m.feedUrl)
end sub

function getFeedUrlFromManifest() as dynamic
    appInfo = CreateObject("roAppInfo")
    return appInfo.GetValue("feed_url")
end function

sub loadChannels(url as string)
    m.list.content = invalid
    task = CreateObject("roSGNode", "GetChannelList")
    task.url = url
    task.ObserveField("content", "onContentReady")
    task.control = "run"
end sub

sub onContentReady()
    content = m.top.FindNode("GetChannelList") ' not needed; we get via event parameter in SG, but we'll use m for simplicity
    ' Instead, the task sent its content in the event, fetch from the field
    task = m.top.GetChild(0) ' fragile; better to store, but okay for demo
end sub

' SG sends field change events differently; easiest is to observe on the task object itself.
' We'll store the task and handle in a separate handler:
sub onTaskContentChanged()
end sub

' Our Task calls back into the scene by setting the list's content directly when done.
' (See task implementation.)

sub onItemSelected()
    idx = m.list.itemSelected
    item = m.list.content.getChild(idx)
    if item <> invalid and item.stream <> invalid
        m.video.content = CreateObject("roSGNode", "ContentNode")
        m.video.content.title = item.title
        m.video.content.stream = item.stream
        m.video.content.streamformat = item.streamformat
        m.video.control = "play"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "options" ' * key
        m.kbd.text = m.feedUrl
        m.kbd.visible = true
        m.kbd.observeField("buttonSelected", "onKbdButton")
        return true
    end if

    if key = "back"
        if m.video <> invalid and m.video.state = "playing"
            m.video.control = "stop"
            return true
        end if
    end if

    return false
end function

sub onKbdButton()
    ' button 0 is OK/submit in KeyboardDialog
    if m.kbd.buttonSelected = 0
        m.feedUrl = m.kbd.text
        m.kbd.visible = false
        loadChannels(m.feedUrl)
    else
        m.kbd.visible = false
    end if
end sub
