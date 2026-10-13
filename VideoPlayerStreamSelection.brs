'import "pkg:/source/Format.bs"
'---------------------------------------------------------------------------
' VideoPlayerStreamSelection.__GetStreams
'---------------------------------------------------------------------------
function VideoPlayerStreamSelection___GetStreams(item as dynamic, streamType as string) as object
    if item = invalid or item.MediaStreams = invalid then
        return []
    end if
    streams = []
    targetType = LCase(streamType)
    for each stream in item.MediaStreams
        if stream <> invalid and LCase(Format_SafeString(stream.Type, "")) = targetType then
            streams.Push(stream)
        end if
    end for
    return streams
end function

'---------------------------------------------------------------------------
' VideoPlayerStreamSelection.GetSubtitleStreams
'---------------------------------------------------------------------------
function VideoPlayerStreamSelection_GetSubtitleStreams(item as dynamic) as object
    return VideoPlayerStreamSelection___GetStreams(item, "subtitle")
end function

'---------------------------------------------------------------------------
' VideoPlayerStreamSelection.GetAudioStreams
'---------------------------------------------------------------------------
function VideoPlayerStreamSelection_GetAudioStreams(item as dynamic) as object
    return VideoPlayerStreamSelection___GetStreams(item, "audio")
end function