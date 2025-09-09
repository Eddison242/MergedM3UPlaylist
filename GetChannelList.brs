sub init()
    m.top.functionName = "runTask"
end sub

sub runTask()
    url = m.top.url
    if url = invalid or url = ""
        url = "http://m3u4u.com/m3u/4z2xnjk284a2qek9yv15"
    end if

    listContent = CreateObject("roSGNode", "ContentNode")

    port = CreateObject("roMessagePort")
    req = CreateObject("roUrlTransfer")
    req.SetMessagePort(port)
    req.SetCertificatesFile("common:/certs/ca-bundle.crt")
    req.InitClientCertificates()
    req.SetUrl(url)

    data = req.GetToString()
    if data = invalid then
        m.top.content = listContent
        return
    end if

    lines = data.Split(chr(10))
    title = invalid
    logo = invalid

    for i = 0 to lines.Count() - 1
        line = Trim(lines[i])
        if Left(line, 7) = "#EXTINF"
            ' extract title after comma
            commaIdx = Instr(1, line, ",")
            if commaIdx > 0
                title = Mid(line, commaIdx + 1)
            else
                title = "Channel"
            end if
        else if line <> "" and Left(line, 1) <> "#"
            streamUrl = line
            item = CreateObject("roSGNode", "ContentNode")
            item.title = title
            item.stream = { url: streamUrl }
            if Right(streamUrl, 5) = ".m3u8"
                item.streamformat = "hls"
            else
                item.streamformat = "mp4"
            end if
            listContent.appendChild(item)
        end if
    end for

    m.top.content = listContent
end sub
