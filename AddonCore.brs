'import "pkg:/source/store/LocalAccountStore.bs"
' Stremio addon protocol core — shared by all Tasks and the MainScene.
' Every HTTP read goes through HttpGetJson, which is async with a hard
' timeout so a dead addon can never freeze the app again.

'-------------------------------------------------------------------------------
' NormalizeManifestUrl
'-------------------------------------------------------------------------------
function NormalizeManifestUrl(rawValue as dynamic) as string
    resultUrl = AddonStringText(rawValue).Trim()
    if resultUrl = "" then
        return ""
    end if
    if AddonTextHasControls(resultUrl) then return ""
    fragmentPosition = Instr(1, resultUrl, "#")
    if fragmentPosition > 0 then
        resultUrl = Left(resultUrl, fragmentPosition - 1)
    end if
    query = ""
    queryPosition = Instr(1, resultUrl, "?")
    if queryPosition > 0
        query = Mid(resultUrl, queryPosition)
        resultUrl = Left(resultUrl, queryPosition - 1)
        ' Repair links persisted by the older suffix-only normalizer.
        if Left(LCase(query), 3) = "?v=" and Right(LCase(query), 14) = "/manifest.json"
            query = Left(query, Len(query) - 14)
        end if
    end if
    lowerValue = LCase(resultUrl)
    if Left(lowerValue, 10) = "stremio://" then
        resultUrl = "https://" + Mid(resultUrl, 11)
    end if
    lowerValue = LCase(resultUrl)
    if Left(lowerValue, 7) <> "http://" and Left(lowerValue, 8) <> "https://" then
        if Instr(1, resultUrl, "://") > 0 then return ""
        resultUrl = "https://" + resultUrl
    end if
    if AddonHttpUrl(resultUrl) = "" then return ""
    while Len(resultUrl) > 0 and Right(resultUrl, 1) = "/"
        resultUrl = Left(resultUrl, Len(resultUrl) - 1)
    end while
    if Right(LCase(resultUrl), 14) <> "/manifest.json" then
        resultUrl = resultUrl + "/manifest.json"
    end if
    ' Addon configuration URLs are often generated with spaces, pipes and
    ' Unicode directly in the path. Android may accept those after URL
    ' normalization, but Roku's HTTP stack is stricter. Encode only the path,
    ' preserving scheme, host, slashes, existing %XX escapes and query text.
    resultUrl = NormalizeAddonUrlPath(resultUrl)
    return resultUrl + query
end function

'-------------------------------------------------------------------------------
' NormalizeAddonUrlPath
'-------------------------------------------------------------------------------
function NormalizeAddonUrlPath(value as string) as string
    schemePosition = Instr(1, value, "://")
    if schemePosition <= 0 then
        return value
    end if
    authorityStart = schemePosition + 3
    pathPosition = Instr(authorityStart, value, "/")
    if pathPosition <= 0 then
        return value
    end if
    prefix = Left(value, pathPosition - 1)
    path = Mid(value, pathPosition)
    result = prefix
    for i = 1 to Len(path)
        character = Mid(path, i, 1)
        if character = "%" and i + 2 <= Len(path)
            h1 = Mid(path, i + 1, 1)
            h2 = Mid(path, i + 2, 1)
            if IsHexUrlChar(h1) and IsHexUrlChar(h2)
                result = result + character + h1 + h2
                i = i + 2
                continue for
            end if
        end if
        if character = " " then
            result = result + "%20"
        else if character = "|" then
            result = result + "%7C"
        else if Asc(character) > 127 then
            result = result + UrlEncodeUnicodeCharacter(character)
        else
            result = result + character
        end if
    end for
    return result
end function

'-------------------------------------------------------------------------------
' UrlEncodeUnicodeCharacter
'-------------------------------------------------------------------------------
function UrlEncodeUnicodeCharacter(character as string) as string
    if character = "" then
        return ""
    end if
    codePoint = Asc(character)
    if codePoint <= 127 then
        return character
    end if
    if codePoint <= 2047
        byte1 = 192 + Int(codePoint / 64)
        byte2 = 128 + (codePoint Mod 64)
        return "%" + HexByte(byte1) + "%" + HexByte(byte2)
    end if
    if codePoint <= 65535
        byte1 = 224 + Int(codePoint / 4096)
        remainder = codePoint Mod 4096
        byte2 = 128 + Int(remainder / 64)
        byte3 = 128 + (remainder Mod 64)
        return "%" + HexByte(byte1) + "%" + HexByte(byte2) + "%" + HexByte(byte3)
    end if
    byte1 = 240 + Int(codePoint / 262144)
    remainder = codePoint Mod 262144
    byte2 = 128 + Int(remainder / 4096)
    remainder = remainder Mod 4096
    byte3 = 128 + Int(remainder / 64)
    byte4 = 128 + (remainder Mod 64)
    return "%" + HexByte(byte1) + "%" + HexByte(byte2) + "%" + HexByte(byte3) + "%" + HexByte(byte4)
end function

'-------------------------------------------------------------------------------
' HexByte
'-------------------------------------------------------------------------------
function HexByte(value as integer) as string
    digits = "0123456789ABCDEF"
    high = Int(value / 16)
    low = value Mod 16
    return Mid(digits, high + 1, 1) + Mid(digits, low + 1, 1)
end function

'-------------------------------------------------------------------------------
' IsHexUrlChar
'-------------------------------------------------------------------------------
function IsHexUrlChar(value as string) as boolean
    if Len(value) <> 1 then
        return false
    end if
    code = Asc(LCase(value))
    return (code >= 48 and code <= 57) or (code >= 97 and code <= 102)
end function

'-------------------------------------------------------------------------------
' AddonBaseUrl
'-------------------------------------------------------------------------------
function AddonBaseUrl(manifestValue as string) as string
    resultUrl = NormalizeManifestUrl(manifestValue)
    queryPosition = Instr(1, resultUrl, "?")
    if queryPosition > 0 then
        resultUrl = Left(resultUrl, queryPosition - 1)
    end if
    suffix = "/manifest.json"
    if Len(resultUrl) >= Len(suffix) and Right(LCase(resultUrl), Len(suffix)) = suffix
        return Left(resultUrl, Len(resultUrl) - Len(suffix))
    end if
    return resultUrl
end function

'-------------------------------------------------------------------------------
' AddonQuerySuffix
'-------------------------------------------------------------------------------
function AddonQuerySuffix(manifestValue as string) as string
    normalized = NormalizeManifestUrl(manifestValue)
    queryPosition = Instr(1, normalized, "?")
    if queryPosition <= 0 then
        return ""
    end if
    return Mid(normalized, queryPosition)
end function

'-------------------------------------------------------------------------------
' AddonResourceName
'-------------------------------------------------------------------------------
function AddonResourceName(resource as dynamic) as string
    if resource = invalid then
        return ""
    end if
    if type(resource) = "roString" or type(resource) = "String"
        return resource.ToStr().Trim()
    end if
    if type(resource) = "roAssociativeArray"
        if resource.name <> invalid then
            return AddonScalarText(resource.name).Trim()
        end if
        if resource.resource <> invalid then
            return AddonScalarText(resource.resource).Trim()
        end if
        if resource.id <> invalid then
            return AddonScalarText(resource.id).Trim()
        end if
    end if
    return ""
end function

'-------------------------------------------------------------------------------
' ArrayContainsString
'-------------------------------------------------------------------------------
function ArrayContainsString(values as dynamic, needle as string, caseSensitive = false as boolean) as boolean
    if values = invalid then
        return false
    end if
    if type(values) <> "roArray" then
        return false
    end if
    target = needle
    if not caseSensitive then target = LCase(target)
    for each value in values
        text = AddonScalarText(value)
        if not caseSensitive then text = LCase(text)
        if text = target then
            return true
        end if
    end for
    return false
end function

'-------------------------------------------------------------------------------
' IdMatchesPrefixes
'-------------------------------------------------------------------------------
function IdMatchesPrefixes(id as string, prefixes as dynamic) as boolean
    if prefixes = invalid then
        return true
    end if
    if type(prefixes) <> "roArray" then
        return true
    end if
    if prefixes.Count() = 0 then
        return true
    end if
    for each prefix in prefixes
        p = AddonStringText(prefix)
        if p <> "" and Left(id, Len(p)) = p then
            return true
        end if
    end for
    return false
end function

'-------------------------------------------------------------------------------
' UrlEncodeComponent
'-------------------------------------------------------------------------------
function UrlEncodeComponent(raw as dynamic) as string
    if raw = invalid then
        return ""
    end if
    text = AddonScalarText(raw)
    transfer = CreateObject("roUrlTransfer")
    return transfer.UrlEncode(text)
end function

'-------------------------------------------------------------------------------
' AddonSupports
'-------------------------------------------------------------------------------
function AddonSupports(descriptor as dynamic, resourceName as string, mediaType as string, mediaId as string) as boolean
    if descriptor = invalid or Type(descriptor) <> "roAssociativeArray" then
        return false
    end if
    if descriptor.manifest = invalid or Type(descriptor.manifest) <> "roAssociativeArray" then return false
    if descriptor.enabled <> invalid and descriptor.enabled = false then
        return false
    end if
    manifest = descriptor.manifest
    if manifest.resources <> invalid and type(manifest.resources) = "roArray"
        for each resource in manifest.resources
            if LCase(AddonResourceName(resource)) = LCase(resourceName)
                types = manifest.types
                prefixes = manifest.idPrefixes
                if type(resource) = "roAssociativeArray" then
                    if resource.types <> invalid then
                        types = resource.types
                    else if AddonStringText(resource.type) <> "" then
                        types = [resource.type]
                    end if
                    ' Full resource declarations have their own optional ID
                    ' filter. An absent filter means all IDs, not the manifest's
                    ' filter (which only applies to string declarations).
                    prefixes = resource.idPrefixes
                end if
                if mediaType <> "" and types <> invalid and not ArrayContainsString(types, mediaType, true) then continue for
                ' Catalog IDs belong to manifest.catalogs; idPrefixes only
                ' filter content resources, never catalog identifiers.
                if LCase(resourceName) <> "catalog" and mediaId <> "" and not IdMatchesPrefixes(mediaId, prefixes) then continue for
                return true
            end if
        end for
    end if
    return false
end function

'-------------------------------------------------------------------------------
' AddonManifestNeedsConfiguration
'-------------------------------------------------------------------------------
function AddonManifestNeedsConfiguration(manifest as dynamic) as boolean
    if manifest = invalid or Type(manifest) <> "roAssociativeArray" then
        return false
    end if
    if manifest.behaviorHints = invalid or Type(manifest.behaviorHints) <> "roAssociativeArray" then
        return false
    end if
    if manifest.behaviorHints.configurationRequired = invalid or manifest.behaviorHints.configurationRequired <> true then
        return false
    end if
    ' The flag means configuration is required even if the public manifest
    ' advertises resources/catalogs. Installing it unconfigured can result in
    ' empty catalog and stream lists or unauthorized responses.
    return true
end function

'-------------------------------------------------------------------------------
' CatalogExtraDefaultValue
'-------------------------------------------------------------------------------
function CatalogExtraDefaultValue(extra as dynamic) as string
    if extra = invalid or Type(extra) <> "roAssociativeArray" then
        return ""
    end if
    defaultValue = AddonScalarText(extra.defaultValue)
    if defaultValue = "" then defaultValue = AddonScalarText(extra.default)
    if defaultValue <> "" then return defaultValue
    if extra.options <> invalid and Type(extra.options) = "roArray"
        firstValue = ""
        for each optionValue in extra.options
            textValue = AddonScalarText(optionValue)
            if textValue = "" then
                continue for
            end if
            if firstValue = "" then
                firstValue = textValue
            end if
            if LCase(textValue) = "none" then
                return textValue
            end if
        end for
        return firstValue
    end if
    return ""
end function

'-------------------------------------------------------------------------------
' BuildCatalogDefaultExtras
'-------------------------------------------------------------------------------
function BuildCatalogDefaultExtras(catalog as dynamic) as dynamic
    defaults = {}
    for each extra in CatalogExtraDefinitions(catalog)
        if extra = invalid or Type(extra) <> "roAssociativeArray" then
            continue for
        end if
        if extra.isRequired = invalid or extra.isRequired <> true then
            continue for
        end if
        if AddonScalarText(extra.name) = "" then
            return invalid
        end if
        defaultValue = CatalogExtraDefaultValue(extra)
        if defaultValue = "" then
            return invalid
        end if
        defaults[AddonScalarText(extra.name)] = defaultValue
    end for
    return defaults
end function

'-------------------------------------------------------------------------------
' BuildCatalogRequestExtras
'-------------------------------------------------------------------------------
function BuildCatalogRequestExtras(catalog as dynamic, provided = invalid as dynamic) as dynamic
    extras = {}
    if provided <> invalid and Type(provided) = "roAssociativeArray"
        for each key in provided
            if AddonScalarText(provided[key]) <> "" then
                extras[key] = provided[key]
            end if
        end for
    end if
    for each extra in CatalogExtraDefinitions(catalog)
        if extra = invalid or Type(extra) <> "roAssociativeArray" or extra.name = invalid then
            continue for
        end if
        name = AddonScalarText(extra.name)
        if name = "" then
            continue for
        end if
        if AddonScalarText(extras[name]) <> "" then
            continue for
        end if
        ' Only send a language preference when the addon explicitly exposes
        ' a language extra. Never append undocumented URL parameters.
        if LCase(name) = "language" or LCase(name) = "lang" or LCase(name) = "locale"
            localeValue = AddonCatalogLocaleOption(extra, I18n_ReadLanguage())
            if localeValue <> ""
                extras[name] = localeValue
                continue for
            end if
        end if
        if extra.isRequired <> invalid and extra.isRequired = true
            defaultValue = CatalogExtraDefaultValue(extra)
            if defaultValue = "" then
                return invalid
            end if
            extras[name] = defaultValue
        end if
    end for
    return extras
end function

'-------------------------------------------------------------------------------
' AddonCatalogLocaleOption
'-------------------------------------------------------------------------------
function AddonCatalogLocaleOption(extra as dynamic, language as string) as string
    if extra = invalid or Type(extra) <> "roAssociativeArray" then return ""
    if extra.options = invalid or Type(extra.options) <> "roArray" then return ""
    preferred = ["pt-BR", "pt", "por"]
    if language = "en" then preferred = ["en", "en-US", "eng"]
    if language = "es" then preferred = ["es", "es-ES", "spa"]
    for each target in preferred
        for each option in extra.options
            value = AddonScalarText(option)
            if LCase(value) = LCase(target) then return value
        end for
    end for
    return ""
end function

'-------------------------------------------------------------------------------
' CatalogHasRequiredExtras
'-------------------------------------------------------------------------------
function CatalogHasRequiredExtras(catalog as dynamic) as boolean
    for each extra in CatalogExtraDefinitions(catalog)
        if extra <> invalid and type(extra) = "roAssociativeArray"
            if extra.isRequired <> invalid and extra.isRequired = true
                return true
            end if
        end if
    end for
    return false
end function
' Catalog extras the client actually sends. Search/pagination are passed as
' the third path segment: /catalog/{type}/{id}/{extra}.json

'-------------------------------------------------------------------------------
' BuildCatalogUrl
'-------------------------------------------------------------------------------
function BuildCatalogUrl(descriptor as dynamic, catalog as dynamic, extra = invalid as dynamic) as string
    if Type(descriptor) <> "roAssociativeArray" or Type(catalog) <> "roAssociativeArray" then
        return ""
    end if
    if AddonStringText(descriptor.transportUrl) = "" then
        return ""
    end if
    if AddonStringText(catalog.type) = "" or AddonStringText(catalog.id) = "" then
        return ""
    end if
    base = AddonBaseUrl(descriptor.transportUrl.ToStr())
    requestUrl = base + "/catalog/" + UrlEncodeComponent(catalog.type.ToStr()) + "/" + UrlEncodeComponent(catalog.id.ToStr())
    if extra <> invalid and type(extra) = "roAssociativeArray" and extra.Count() > 0
        ' roArray has no Sort() — bubble the keys for a deterministic path.
        keys = []
        for each key in extra
            if AddonScalarText(extra[key]) <> "" then
                keys.Push(key)
            end if
        end for
        for a = 0 to keys.Count() - 2
            for b = a + 1 to keys.Count() - 1
                if LCase(keys[b]) < LCase(keys[a])
                    swapTmp = keys[a]
                    keys[a] = keys[b]
                    keys[b] = swapTmp
                end if
            end for
        end for
        parts = []
        for each key in keys
            parts.Push(UrlEncodeComponent(key) + "=" + UrlEncodeComponent(extra[key]))
        end for
        if parts.Count() > 0 then
            requestUrl = requestUrl + "/" + parts.Join("&")
        end if
    end if
    return requestUrl + ".json" + AddonQuerySuffix(descriptor.transportUrl.ToStr())
end function

'-------------------------------------------------------------------------------
' BuildResourceUrl
'-------------------------------------------------------------------------------
function BuildResourceUrl(descriptor as dynamic, resourceName as string, mediaType as string, mediaId as string) as string
    if Type(descriptor) <> "roAssociativeArray" then return ""
    if AddonStringText(descriptor.transportUrl) = "" then
        return ""
    end if
    base = AddonBaseUrl(descriptor.transportUrl.ToStr())
    ' Stremio ids are opaque (tt1234, tt1234:1:2, custom ids) — encode them.
    return base + "/" + UrlEncodeComponent(resourceName) + "/" + UrlEncodeComponent(mediaType) + "/" + UrlEncodeComponent(mediaId) + ".json" + AddonQuerySuffix(descriptor.transportUrl.ToStr())
end function

'-------------------------------------------------------------------------------
' BuildResourceUrlWithExtra
'-------------------------------------------------------------------------------
function BuildResourceUrlWithExtra(descriptor as dynamic, resourceName as string, mediaType as string, mediaId as string, extra = invalid as dynamic) as string
    if Type(descriptor) <> "roAssociativeArray" then return ""
    if AddonStringText(descriptor.transportUrl) = "" then
        return ""
    end if
    base = AddonBaseUrl(descriptor.transportUrl.ToStr())
    requestUrl = base + "/" + UrlEncodeComponent(resourceName) + "/" + UrlEncodeComponent(mediaType) + "/" + UrlEncodeComponent(mediaId)
    if extra <> invalid and Type(extra) = "roAssociativeArray" and extra.Count() > 0
        keys = []
        for each key in extra
            if AddonScalarText(extra[key]) <> "" then
                keys.Push(key)
            end if
        end for
        for a = 0 to keys.Count() - 2
            for b = a + 1 to keys.Count() - 1
                if LCase(keys[b]) < LCase(keys[a])
                    tmp = keys[a]
                    keys[a] = keys[b]
                    keys[b] = tmp
                end if
            end for
        end for
        parts = []
        for each key in keys
            parts.Push(UrlEncodeComponent(key) + "=" + UrlEncodeComponent(extra[key]))
        end for
        if parts.Count() > 0 then
            requestUrl = requestUrl + "/" + parts.Join("&")
        end if
    end if
    return requestUrl + ".json" + AddonQuerySuffix(descriptor.transportUrl.ToStr())
end function

'-------------------------------------------------------------------------------
' BuildResourceUrlVariants
'-------------------------------------------------------------------------------
function BuildResourceUrlVariants(descriptor as dynamic, resourceName as string, mediaType as string, mediaId as string) as object
    urls = []
    primary = BuildResourceUrl(descriptor, resourceName, mediaType, mediaId)
    if primary <> "" then
        urls.Push(primary)
    end if
    if Type(descriptor) <> "roAssociativeArray" then return urls
    if AddonStringText(descriptor.transportUrl) = "" then
        return urls
    end if
    base = AddonBaseUrl(descriptor.transportUrl.ToStr())
    ' Some community addons compare the raw Stremio id path literally and do
    ' not decode %3A before routing. Try the spec-compatible encoded URL first,
    ' then the colon-preserving variant only when it is different.
    safeId = UrlEncodeComponent(mediaId).Replace("%3A", ":").Replace("%3a", ":")
    literalColon = base + "/" + UrlEncodeComponent(resourceName) + "/" + UrlEncodeComponent(mediaType) + "/" + safeId + ".json" + AddonQuerySuffix(descriptor.transportUrl.ToStr())
    ' A few community add-ons expect literal colons but still keep the rest of the
    ' path encoded. Preserve the generated query suffix while keeping the id path
    ' in the original colon form. Only append this variant if it is distinct.
    duplicate = false
    for each existingUrl in urls
        if existingUrl = literalColon then
            duplicate = true
        end if
    end for
    if literalColon <> "" and duplicate <> true then
        urls.Push(literalColon)
    end if
    return urls
end function

'-------------------------------------------------------------------------------
' NormalizeStreamPayload
'-------------------------------------------------------------------------------
function NormalizeStreamPayload(payload as dynamic) as object
    streams = []
    if payload = invalid then
        return streams
    end if
    if Type(payload) = "roArray"
        for each raw in payload
            if raw <> invalid and Type(raw) = "roAssociativeArray" then
                streams.Push(raw)
            end if
        end for
        return streams
    end if
    if Type(payload) <> "roAssociativeArray" then
        return streams
    end if
    if payload.streams <> invalid and Type(payload.streams) = "roArray"
        return payload.streams
    end if
    if payload.stream <> invalid and Type(payload.stream) = "roAssociativeArray"
        streams.Push(payload.stream)
        return streams
    end if
    wrappers = [
        payload.data
        payload.result
    ]
    for each wrapper in wrappers
        if wrapper = invalid then
            continue for
        end if
        if Type(wrapper) = "roArray"
            for each raw in wrapper
                if raw <> invalid and Type(raw) = "roAssociativeArray" then
                    streams.Push(raw)
                end if
            end for
            if streams.Count() > 0 then
                return streams
            end if
        else if Type(wrapper) = "roAssociativeArray"
            if wrapper.streams <> invalid and Type(wrapper.streams) = "roArray" then
                return wrapper.streams
            end if
            if wrapper.stream <> invalid and Type(wrapper.stream) = "roAssociativeArray"
                streams.Push(wrapper.stream)
                return streams
            end if
        end if
    end for
    return streams
end function
' Async HTTP GET with a hard timeout. A dead or cold-starting addon must
' fail within milliseconds budget instead of freezing the render thread's
' observer forever.

'-------------------------------------------------------------------------------
' HttpGetJsonResult
'-------------------------------------------------------------------------------
function HttpGetJsonResult(requestUrl as string, timeoutMs = 12000 as integer) as object
    if timeoutMs < 1 then timeoutMs = 12000
    if requestUrl = "" then
        return {
            payload: invalid
            status: 0
            error: "empty-url"
        }
    end if
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(requestUrl)
    transfer.SetMessagePort(port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    transfer.EnableEncodings(true)
    transfer.AddHeader("Accept", "application/json")
    transfer.AddHeader("Accept-Language", I18n_ReadLanguage())
    transfer.AddHeader("User-Agent", "Stremio-Roku/1.8.9")
    transfer.RetainBodyOnError(true)
    if not transfer.AsyncGetToString() then
        return {
            payload: invalid
            status: 0
            error: "request-start-failed"
        }
    end if
    deadline = CreateObject("roTimespan")
    deadline.Mark()
    while true
        remaining = timeoutMs - deadline.TotalMilliseconds()
        if remaining < 1
            transfer.AsyncCancel()
            return {
                payload: invalid
                status: 0
                error: "timeout"
            }
        end if
        if remaining > 500 then remaining = 500
        msg = wait(remaining, port)
        if msg <> invalid and type(msg) = "roUrlEvent"
            code = msg.GetResponseCode()
            body = msg.GetString()
            if code < 200 or code >= 300 then
                return {
                    payload: invalid
                    status: code
                    error: "http-status"
                }
            end if
            if body = invalid or body = "" then
                return {
                    payload: invalid
                    status: code
                    error: "empty-response"
                }
            end if
            if Len(body) > 4194304 then
                return { payload: invalid, status: code, error: "response-too-large" }
            end if
            payload = ParseJson(body)
            if payload = invalid then
                return {
                    payload: invalid
                    status: code
                    error: "invalid-json"
                }
            end if
            return {
                payload: payload
                status: code
                error: ""
            }
        end if
    end while
end function

'-------------------------------------------------------------------------------
' HttpGetJson
'-------------------------------------------------------------------------------
function HttpGetJson(requestUrl as string, timeoutMs = 12000 as integer) as dynamic
    response = HttpGetJsonResult(requestUrl, timeoutMs)
    if response.error <> "" then
        return invalid
    end if
    return response.payload
end function

'-------------------------------------------------------------------------------
' AddonInstallFetchError
'-------------------------------------------------------------------------------
function AddonInstallFetchError(response as dynamic) as string
    if response = invalid or Type(response) <> "roAssociativeArray"
        return I18n_T("Não foi possível ler o manifest.json do addon.")
    end if
    status = Number_ToInteger(response.status, 0)
    failure = Format_SafeString(response.error, "")
    if status = 403
        return I18n_T("O servidor do addon recusou o acesso (HTTP 403). Verifique se há um link pessoal/configurado ou peça ao mantenedor para liberar o acesso do Roku.")
    end if
    if status = 429
        return I18n_T("O servidor do addon limitou as tentativas (HTTP 429). Aguarde e tente novamente.")
    end if
    if status >= 400
        return I18n_T("O servidor do addon respondeu com HTTP ") + status.ToStr() + I18n_T(". Verifique o link de instalação.")
    end if
    if failure = "timeout"
        return I18n_T("O addon demorou demais para responder. Verifique a conexão ou tente novamente mais tarde.")
    end if
    if failure = "invalid-json"
        return I18n_T("O endereço respondeu, mas não enviou um manifest.json válido.")
    end if
    if failure = "empty-response"
        return I18n_T("O servidor do addon respondeu sem conteúdo para o manifest.json.")
    end if
    if failure = "empty-url"
        return I18n_T("URL do manifest vazia.")
    end if
    return I18n_T("Não foi possível conectar ao servidor do addon. Verifique o endereço e a conexão do Roku.")
end function

'-------------------------------------------------------------------------------
' HttpGetJsonParallel
'-------------------------------------------------------------------------------
function HttpGetJsonParallel(requests as dynamic, timeoutMs = 12000 as integer) as object
    if timeoutMs < 1 then timeoutMs = 12000
    results = []
    if requests = invalid or Type(requests) <> "roArray" or requests.Count() = 0 then return results
    port = CreateObject("roMessagePort")
    pending = {}
    nextIndex = 0
    ' SceneGraph Tasks still have finite heap. Starting 60 simultaneous
    ' requests creates 60 transfer buffers and can cause memory pressure.
    ' A bounded pool preserves the original shared time budget.
    maxInFlight = 12
    preferredLanguage = I18n_ReadLanguage()
    deadline = CreateObject("roTimespan")
    deadline.Mark()
    while (nextIndex < requests.Count() or pending.Count() > 0) and deadline.TotalMilliseconds() < timeoutMs
        while nextIndex < requests.Count() and pending.Count() < maxInFlight
            requestIndex = nextIndex
            nextIndex = nextIndex + 1
            request = requests[requestIndex]
            requestUrl = ""
            if Type(request) = "roAssociativeArray" then requestUrl = AddonStringText(request.url)
            if requestUrl = "" then
                results.Push({ request: request, index: requestIndex, status: 0, payload: invalid, error: "empty-url" })
                continue while
            end if
            transfer = CreateObject("roUrlTransfer")
            transfer.SetUrl(requestUrl)
            transfer.SetMessagePort(port)
            transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
            transfer.InitClientCertificates()
            transfer.EnableEncodings(true)
            transfer.AddHeader("Accept", "application/json")
            transfer.AddHeader("Accept-Language", preferredLanguage)
            transfer.AddHeader("User-Agent", "Stremio-Roku/1.8.9")
            transfer.RetainBodyOnError(true)
            if transfer.AsyncGetToString()
                identity = transfer.GetIdentity().ToStr()
                pending[identity] = { transfer: transfer, request: request, index: requestIndex }
            else
                results.Push({ request: request, index: requestIndex, status: 0, payload: invalid, error: "request-start-failed" })
            end if
        end while
        if pending.Count() = 0 then
            if nextIndex >= requests.Count() then exit while
            continue while
        end if
        remaining = timeoutMs - deadline.TotalMilliseconds()
        if remaining <= 0 then exit while
        waitMs = 250
        if remaining < waitMs then waitMs = remaining
        msg = wait(waitMs, port)
        if msg = invalid or Type(msg) <> "roUrlEvent" then continue while
        identity = msg.GetSourceIdentity().ToStr()
        entry = pending[identity]
        if entry = invalid then continue while
        code = msg.GetResponseCode()
        body = msg.GetString()
        payload = invalid
        errorText = ""
        if code >= 200 and code < 300 and body <> invalid and body <> ""
            if Len(body) > 4194304
                errorText = "response-too-large"
            else
                payload = ParseJson(body)
                if payload = invalid then errorText = "invalid-json"
            end if
        else if code >= 200 and code < 300
            errorText = "empty-response"
        else
            errorText = "http-status"
        end if
        results.Push({ request: entry.request, index: entry.index, status: code, payload: payload, error: errorText })
        pending.Delete(identity)
    end while
    if pending.Count() > 0
        pendingKeys = []
        for each identity in pending
            pendingKeys.Push(identity)
        end for
        for each identity in pendingKeys
            entry = pending[identity]
            if entry <> invalid and entry.transfer <> invalid then entry.transfer.AsyncCancel()
            results.Push({ request: entry.request, index: entry.index, status: 0, payload: invalid, error: "timeout" })
            pending.Delete(identity)
        end for
    end if
    ' Keep the response contract: each input index produces one result even
    ' when the global deadline expires before its turn in the queue.
    for requestIndex = nextIndex to requests.Count() - 1
        results.Push({ request: requests[requestIndex], index: requestIndex, status: 0, payload: invalid, error: "timeout" })
    end for
    return results
end function

'-------------------------------------------------------------------------------
' NormalizeSubtitlePayload
'-------------------------------------------------------------------------------
function NormalizeSubtitlePayload(payload as dynamic) as object
    subtitles = []
    if payload = invalid then
        return subtitles
    end if
    if Type(payload) = "roArray" then
        return payload
    end if
    if Type(payload) <> "roAssociativeArray" then
        return subtitles
    end if
    if payload.subtitles <> invalid and Type(payload.subtitles) = "roArray" then
        return payload.subtitles
    end if
    if payload.data <> invalid
        if Type(payload.data) = "roArray" then
            return payload.data
        end if
        if Type(payload.data) = "roAssociativeArray" and payload.data.subtitles <> invalid and Type(payload.data.subtitles) = "roArray" then
            return payload.data.subtitles
        end if
    end if
    if payload.result <> invalid
        if Type(payload.result) = "roArray" then
            return payload.result
        end if
        if Type(payload.result) = "roAssociativeArray" and payload.result.subtitles <> invalid and Type(payload.result.subtitles) = "roArray" then
            return payload.result.subtitles
        end if
    end if
    return subtitles
end function

'-------------------------------------------------------------------------------
' LoadInstalledAddons
'-------------------------------------------------------------------------------
function LoadInstalledAddons() as object
    section = CreateObject("roRegistrySection", "StremioRoku")
    raw = ""
    chunkCount = 0
    chunkCountRaw = section.Read("addons_chunk_count")
    if chunkCountRaw <> invalid and chunkCountRaw <> "" then
        chunkCount = Val(chunkCountRaw)
    end if
    if chunkCount > 0 and chunkCount <= 32
        for chunkIndex = 0 to chunkCount - 1
            part = section.Read("addons_chunk_" + chunkIndex.ToStr())
            if part = invalid or part = ""
                raw = ""
                exit for
            end if
            raw = raw + part
        end for
    end if
    ' Backward compatibility with the old single-value registry format.
    if raw = ""
        legacy = section.Read("addons")
        if legacy <> invalid then
            raw = legacy
        end if
    end if
    if raw = invalid or raw = "" then
        return []
    end if
    parsed = ParseJson(raw)
    if parsed = invalid or Type(parsed) <> "roArray" then
        return []
    end if
    output = []
    for each descriptor in parsed
        compact = CompactAddonDescriptor(descriptor)
        if compact <> invalid then
            output.Push(compact)
        end if
    end for
    return output
end function

'-------------------------------------------------------------------------------
' SaveInstalledAddons
'-------------------------------------------------------------------------------
function SaveInstalledAddons(addons as object) as boolean
    compact = []
    if addons <> invalid
        for each descriptor in addons
            normalized = CompactAddonDescriptor(descriptor)
            if normalized <> invalid then
                compact.Push(normalized)
            end if
            if compact.Count() > 60 then
                return false
            end if
        end for
    end if
    jsonText = FormatJson(compact)
    section = CreateObject("roRegistrySection", "StremioRoku")
    previousCount = 0
    previousCountRaw = section.Read("addons_chunk_count")
    if previousCountRaw <> invalid and previousCountRaw <> "" then
        previousCount = Val(previousCountRaw)
    end if
    if previousCount < 0 then
        previousCount = 0
    end if
    if previousCount > 32 then
        previousCount = 32
    end if
    chunkSize = 18000
    chunkCount = 1
    if Len(jsonText) > 0 then
        chunkCount = Int((Len(jsonText) + chunkSize - 1) / chunkSize)
    end if
    if chunkCount < 1 then
        chunkCount = 1
    end if
    if chunkCount > 32 then
        return false
    end if
    writesOk = true
    for chunkIndex = 0 to chunkCount - 1
        startPosition = (chunkIndex * chunkSize) + 1
        part = Mid(jsonText, startPosition, chunkSize)
        if not section.Write("addons_chunk_" + chunkIndex.ToStr(), part) then
            writesOk = false
        end if
    end for
    if writesOk
        writesOk = section.Write("addons_chunk_count", chunkCount.ToStr())
    end if
    if writesOk
        section.Delete("addons")
        if previousCount > chunkCount
            for staleIndex = chunkCount to previousCount - 1
                section.Delete("addons_chunk_" + staleIndex.ToStr())
            end for
        end if
        return section.Flush()
    end if
    return false
end function

'-------------------------------------------------------------------------------
' CompactAddonDescriptor
'-------------------------------------------------------------------------------
function AddonManifestIsValid(manifest as dynamic) as boolean
    if manifest = invalid or Type(manifest) <> "roAssociativeArray" then return false
    for each fieldName in ["id", "name", "version"]
        value = manifest[fieldName]
        valueType = Type(value)
        if valueType <> "String" and valueType <> "roString" then return false
        if value.ToStr().Trim() = "" then return false
    end for
    for each fieldName in ["resources", "types", "catalogs"]
        value = manifest[fieldName]
        if value <> invalid and Type(value) <> "roArray" then return false
    end for
    return true
end function

' Protocol payloads may contain malformed objects where a scalar is expected.
' Optional malformed values are skipped instead of invoking a missing ToStr().
function AddonScalarText(value as dynamic, fallback = "" as string) as string
    valueType = Type(value)
    if valueType = "String" or valueType = "roString" or valueType = "Boolean" or valueType = "roBoolean" or Number___IsNumericType(valueType) then return value.ToStr()
    return fallback
end function

' Locator fields must be strings. Numbers and booleans are useful for catalog
' extras, but must never become invented URLs or opaque content identifiers.
function AddonStringText(value as dynamic, fallback = "" as string) as string
    valueType = Type(value)
    if valueType = "String" or valueType = "roString" then return value.ToStr()
    return fallback
end function

function CompactAddonDescriptor(descriptor as dynamic) as dynamic
    if descriptor = invalid or Type(descriptor) <> "roAssociativeArray" then
        return invalid
    end if
    transportUrl = ""
    if Type(descriptor.transportUrl) = "String" or Type(descriptor.transportUrl) = "roString" then
        transportUrl = NormalizeManifestUrl(descriptor.transportUrl)
    end if
    if transportUrl = "" then
        return invalid
    end if
    manifest = descriptor.manifest
    if not AddonManifestIsValid(manifest) then
        return invalid
    end if
    compactManifest = {
        id: manifest.id
        name: manifest.name
        version: manifest.version
        resources: CompactAddonResources(manifest.resources)
        types: CompactStringArray(manifest.types)
        idPrefixes: CompactStringArray(manifest.idPrefixes)
        catalogs: CompactAddonCatalogs(manifest.catalogs)
    }
    description = AddonScalarText(manifest.description)
    if description <> "" then I18n_Set(compactManifest, "description", Left(description, 480))
    for each fieldName in ["logo", "icon", "background", "contactEmail"]
        textValue = AddonScalarText(manifest[fieldName])
        if textValue <> "" then compactManifest[fieldName] = textValue
    end for
    if manifest.addonCatalogs <> invalid then
        compactManifest.addonCatalogs = CompactAddonCatalogs(manifest.addonCatalogs)
    end if
    if manifest.config <> invalid then
        compactManifest.config = CompactAddonConfig(manifest.config)
    end if
    if manifest.behaviorHints <> invalid and Type(manifest.behaviorHints) = "roAssociativeArray"
        compactManifest.behaviorHints = {}
        hintKeys = [
            "configurable"
            "configurationRequired"
            "adult"
            "p2p"
            "epgProvider"
        ]
        for each hintKey in hintKeys
            if manifest.behaviorHints[hintKey] <> invalid then
                compactManifest.behaviorHints[hintKey] = manifest.behaviorHints[hintKey]
            end if
        end for
    end if
    enabled = true
    if descriptor.enabled <> invalid then
        enabled = descriptor.enabled
    end if
    return {
        manifest: compactManifest
        transportUrl: transportUrl
        enabled: enabled
    }
end function

'-------------------------------------------------------------------------------
' CompactAddonConfig
'-------------------------------------------------------------------------------
function CompactAddonConfig(config as dynamic) as object
    output = []
    if config = invalid or Type(config) <> "roArray" then
        return output
    end if
    for each entry in config
        if entry = invalid or Type(entry) <> "roAssociativeArray" or entry.key = invalid or entry.type = invalid then
            continue for
        end if
        configKey = AddonScalarText(entry.key)
        configType = AddonScalarText(entry.type)
        if configKey = "" or configType = "" then continue for
        item = { key: configKey, type: configType }
        if entry.title <> invalid then
            I18n_Set(item, "title", Left(AddonScalarText(entry.title), 160))
        end if
        if entry.default <> invalid then
            item.default = AddonScalarText(entry.default)
        end if
        if entry.required <> invalid then
            item.required = entry.required
        end if
        if entry.options <> invalid and Type(entry.options) = "roArray" then
            item.options = CompactStringArray(entry.options)
        end if
        output.Push(item)
        if output.Count() >= 80 then
            exit for
        end if
    end for
    return output
end function

'-------------------------------------------------------------------------------
' CompactAddonResources
'-------------------------------------------------------------------------------
function CompactAddonResources(resources as dynamic) as object
    output = []
    if resources = invalid or Type(resources) <> "roArray" then
        return output
    end if
    for each resource in resources
        if resource = invalid then
            continue for
        end if
        if Type(resource) = "roString" or Type(resource) = "String"
            output.Push(resource.ToStr())
        else if Type(resource) = "roAssociativeArray"
            name = AddonResourceName(resource)
            if name = "" then
                continue for
            end if
            item = {
                name: name
            }
            if resource.types <> invalid then
                item.types = CompactStringArray(resource.types)
            else if AddonStringText(resource.type) <> "" then
                item.types = [resource.type]
            end if
            if resource.idPrefixes <> invalid then
                item.idPrefixes = CompactStringArray(resource.idPrefixes)
            end if
            output.Push(item)
        end if
    end for
    return output
end function

'-------------------------------------------------------------------------------
' CompactAddonCatalogs
'-------------------------------------------------------------------------------
function CompactAddonCatalogs(catalogs as dynamic) as object
    output = []
    if catalogs = invalid or Type(catalogs) <> "roArray" then
        return output
    end if
    for each catalog in catalogs
        if catalog = invalid or Type(catalog) <> "roAssociativeArray" then
            continue for
        end if
        catalogType = AddonScalarText(catalog.type)
        catalogId = AddonScalarText(catalog.id)
        if catalogType = "" or catalogId = "" then
            continue for
        end if
        item = {
            type: catalogType
            id: catalogId
            name: AddonScalarText(catalog.name, catalogId)
            extra: CatalogExtraDefinitions(catalog)
        }
        if catalog.showInHome <> invalid then
            item.showInHome = catalog.showInHome
        end if
        output.Push(item)
        if output.Count() >= 240 then
            exit for
        end if
    end for
    return output
end function

'-------------------------------------------------------------------------------
' CompactCatalogExtras
'-------------------------------------------------------------------------------
function CompactCatalogExtras(extras as dynamic) as object
    output = []
    if extras = invalid or Type(extras) <> "roArray" then
        return output
    end if
    for each extra in extras
        if extra = invalid or Type(extra) <> "roAssociativeArray" then
            continue for
        end if
        extraName = AddonScalarText(extra.name)
        if extraName = "" then
            continue for
        end if
        item = {
            name: extraName
        }
        if extra.isRequired <> invalid then
            item.isRequired = extra.isRequired
        end if
        if extra.options <> invalid and Type(extra.options) = "roArray" then
            item.options = CompactStringArray(extra.options)
        end if
        if extra.optionsLimit <> invalid then
            item.optionsLimit = extra.optionsLimit
        end if
        defaultValue = AddonScalarText(extra.defaultValue)
        if defaultValue <> "" then
            item.defaultValue = defaultValue
        end if
        legacyDefault = AddonScalarText(extra.default)
        if legacyDefault <> "" and item.defaultValue = invalid then
            item.defaultValue = legacyDefault
        end if
        output.Push(item)
    end for
    return output
end function

' Old HTTP addons advertise extraSupported/extraRequired instead of extra[].
' Normalize them once so installation, home feeds and search use the same
' contract. Modern declarations keep their options/defaults/required choice.
function CatalogExtraDefinitions(catalog as dynamic) as object
    output = []
    if catalog = invalid or Type(catalog) <> "roAssociativeArray" then return output
    seen = {}
    for each extra in CompactCatalogExtras(catalog.extra)
        name = AddonScalarText(extra.name)
        if seen[name] <> invalid then continue for
        seen[name] = output.Count()
        output.Push(extra)
    end for
    for each names in [catalog.extraSupported, catalog.extraRequired]
        if Type(names) <> "roArray" then continue for
        for each rawName in names
            name = AddonStringText(rawName)
            if name = "" or seen[name] <> invalid then continue for
            seen[name] = output.Count()
            output.Push({ name: name })
        end for
    end for
    if Type(catalog.extraRequired) = "roArray"
        for each rawName in catalog.extraRequired
            name = AddonStringText(rawName)
            if name = "" or seen[name] = invalid then continue for
            extra = output[seen[name]]
            if extra.isRequired = invalid then extra.isRequired = true
        end for
    end if
    return output
end function

'-------------------------------------------------------------------------------
' CompactStringArray
'-------------------------------------------------------------------------------
function CompactStringArray(values as dynamic) as object
    output = []
    if values = invalid or Type(values) <> "roArray" then
        return output
    end if
    for each value in values
        textValue = AddonScalarText(value)
        if textValue <> "" then
            output.Push(textValue)
        end if
    end for
    return output
end function

'-------------------------------------------------------------------------------
' AddonDisplayName
'-------------------------------------------------------------------------------
function AddonDisplayName(descriptor as dynamic) as string
    if descriptor = invalid then
        return "Addon"
    end if
    if descriptor.manifest <> invalid and descriptor.manifest.name <> invalid
        return descriptor.manifest.name.ToStr()
    end if
    return "Addon"
end function
' Real Stremio streams are one of: url | infoHash(+fileIdx) | externalUrl | ytId.
' Only url is directly playable on Roku; everything else is tagged so the UI
' can label it instead of handing the player an unplayable value.

'-------------------------------------------------------------------------------
' PenguStreamRequiresSignIn
'-------------------------------------------------------------------------------
function PenguStreamRequiresSignIn(descriptor as dynamic, raw as dynamic) as boolean
    if descriptor = invalid or Type(descriptor) <> "roAssociativeArray" then return false
    if descriptor.manifest = invalid or Type(descriptor.manifest) <> "roAssociativeArray" then return false
    if LCase(AddonScalarText(descriptor.manifest.id)) <> "com.penguplay" then return false
    if raw = invalid or Type(raw) <> "roAssociativeArray" then return false
    ' The official addon returns a tutorial MP4 when its personal token is
    ' missing/revoked. It is a successful HTTP stream response, not the movie.
    ' Match this one official route only; ordinary clips/other addons survive.
    streamUrl = AddonScalarText(raw.url).Trim()
    signInPattern = CreateObject("roRegex", "^https?://pengu\.uk/signin\.mp4([?#]|$)", "i")
    return signInPattern.IsMatch(streamUrl)
end function

'-------------------------------------------------------------------------------
' NormalizeStream
'-------------------------------------------------------------------------------
function NormalizeStream(raw as dynamic, addonName as string) as dynamic
    if raw = invalid or type(raw) <> "roAssociativeArray" then
        return invalid
    end if
    result = {
        addonName: addonName
        name: "Stream"
        title: ""
        description: ""
        url: ""
        streamFormat: ""
        kind: "http"
        transport: "http"
        playable: true
        unsupportedReason: ""
        locator: ""
        bingeGroup: ""
        notWebReady: false
        filename: ""
        audioLanguage: ""
        audioLanguages: []
        videoHash: ""
        videoSize: 0
        countryWhitelist: []
        httpHeaders: []
        subtitles: []
        responseHeaders: []
    }
    name = AddonScalarText(raw.name)
    if name <> "" then result.name = name
    result.audioLanguage = AddonScalarText(raw.audioLanguage)
    if result.audioLanguage = "" then result.audioLanguage = AddonScalarText(raw.language)
    if result.audioLanguage = "" then result.audioLanguage = AddonScalarText(raw.lang)
    if Type(raw.audioLanguages) = "roArray" then
        result.audioLanguages = CompactStringArray(raw.audioLanguages)
    end if
    description = AddonScalarText(raw.title)
    if AddonScalarText(raw.description) <> "" then description = AddonScalarText(raw.description)
    I18n_Set(result, "description", description)
    I18n_Set(result, "title", description)
    streamUrl = AddonStringText(raw.url).Trim()
    if streamUrl = "" then streamUrl = AddonStringText(raw.streamUrl).Trim()
    if streamUrl = "" then streamUrl = AddonStringText(raw.playbackUrl).Trim()
    if streamUrl = "" then streamUrl = AddonStringText(raw.src).Trim()
    if streamUrl <> ""
        if AddonHttpUrl(streamUrl) <> ""
            result.url = streamUrl
            result.locator = streamUrl
        else
            ' Never turn arbitrary paths, magnet links or malformed HTTP URLs
            ' into a request. Recognized protocol URLs remain diagnosable.
            protocolPattern = CreateObject("roRegex", "^(ftps?|rtmps?|rtsps?)://[^/?# ]+([/?#]|$)", "i")
            if not protocolPattern.IsMatch(streamUrl) or AddonTextHasControls(streamUrl) then return invalid
            result.kind = "protocol"
            result.transport = LCase(Left(streamUrl, Instr(1, streamUrl, ":") - 1))
            result.playable = false
            result.unsupportedReason = "unsupported-protocol"
            result.locator = streamUrl
        end if
    else if AddonStringText(raw.infoHash) <> ""
        result.kind = "torrent"
        result.transport = "bittorrent"
        result.playable = false
        result.unsupportedReason = "torrent-engine-required"
        result.infoHash = AddonStringText(raw.infoHash)
        result.locator = result.infoHash
        result.sources = CompactStringArray(raw.sources)
    else if AddonStringText(raw.externalUrl) <> "" or AddonStringText(raw.playerFrameUrl) <> ""
        result.kind = "external"
        result.transport = "browser"
        result.playable = false
        result.unsupportedReason = "external-player-required"
        result.externalUrl = AddonStringText(raw.externalUrl)
        if result.externalUrl = ""
            result.externalUrl = AddonStringText(raw.playerFrameUrl)
            result.transport = "browser-frame"
        end if
        result.locator = result.externalUrl
    else if AddonStringText(raw.ytId) <> ""
        result.kind = "youtube"
        result.transport = "youtube"
        result.playable = false
        result.unsupportedReason = "youtube-player-required"
        result.ytId = AddonStringText(raw.ytId)
        result.youtubeId = result.ytId
        result.locator = result.ytId
    else if AddonStringText(raw.nzbUrl) <> ""
        result.kind = "usenet"
        result.transport = "nzb"
        result.playable = false
        result.unsupportedReason = "usenet-engine-required"
        result.nzbUrl = AddonStringText(raw.nzbUrl)
        result.locator = result.nzbUrl
    else
        for each archiveField in ["rarUrls", "zipUrls", "7zipUrls", "tgzUrls", "tarUrls"]
            archiveSources = raw[archiveField]
            if Type(archiveSources) <> "roArray" then continue for
            locators = []
            for each archiveSource in archiveSources
                archiveUrl = AddonStringText(archiveSource)
                if Type(archiveSource) = "roAssociativeArray" then archiveUrl = AddonStringText(archiveSource.url)
                if archiveUrl <> "" then locators.Push(archiveUrl)
            end for
            if locators.Count() = 0 then continue for
            result.kind = "archive"
            result.transport = Left(archiveField, Len(archiveField) - 4)
            result.playable = false
            result.unsupportedReason = "archive-engine-required"
            result.locator = locators.Join("|")
            exit for
        end for
        if result.kind = "http" then return invalid
    end if
    if Number___IsNumericType(Type(raw.fileIdx))
        fileIdx = Number_ToFloat(raw.fileIdx, -1)
        if fileIdx >= 0 and fileIdx <= 2147483647
            if fileIdx = Int(fileIdx) then result.fileIdx = Int(fileIdx)
        end if
    end if
    ' Explicit format/MIME declarations help extensionless redirect endpoints;
    ' a known filename extension remains a fallback, never a forced codec.
    result.streamFormat = AddonStreamFormatHint(raw)
    if result.url <> "" then
        if result.streamFormat = "" then result.streamFormat = DetectStreamFormat(result.url)
    end if
    if raw.behaviorHints <> invalid and type(raw.behaviorHints) = "roAssociativeArray"
        hints = raw.behaviorHints
        result.bingeGroup = AddonScalarText(hints.bingeGroup)
        if result.bingeGroup = "" then result.bingeGroup = AddonScalarText(hints.group)
        if hints.notWebReady <> invalid and hints.notWebReady = true then
            result.notWebReady = true
        end if
        result.filename = AddonScalarText(hints.filename)
        result.videoHash = AddonScalarText(hints.videoHash)
        if Number_ToFloat(AddonScalarText(hints.videoSize), 0) > 0 then result.videoSize = AddonScalarText(hints.videoSize)
        if hints.countryWhitelist <> invalid and Type(hints.countryWhitelist) = "roArray" then
            result.countryWhitelist = CompactStringArray(hints.countryWhitelist)
        end if
        if result.streamFormat = "" then result.streamFormat = AddonStreamFormatHint(hints)
        result.httpHeaders = ExtractProxyHeaders(hints)
        result.httpHeaders = MergeHttpHeaders(result.httpHeaders, ExtractLooseHeaders(hints.headers))
        if hints.proxyHeaders <> invalid and type(hints.proxyHeaders) = "roAssociativeArray"
            result.responseHeaders = ExtractLooseHeaders(hints.proxyHeaders.response)
        end if
    end if
    if result.filename = "" then result.filename = AddonScalarText(raw.filename)
    if result.streamFormat = "" then result.streamFormat = AddonFormatFromHeaders(result.responseHeaders)
    if result.streamFormat = "" and result.filename <> "" then result.streamFormat = DetectStreamFormat(result.filename)
    if result.videoHash = "" then result.videoHash = AddonScalarText(raw.videoHash)
    if Number_ToFloat(result.videoSize, 0) <= 0 and Number_ToFloat(AddonScalarText(raw.videoSize), 0) > 0 then result.videoSize = AddonScalarText(raw.videoSize)
    result.httpHeaders = MergeHttpHeaders(result.httpHeaders, ExtractLooseHeaders(raw.httpHeaders))
    result.httpHeaders = MergeHttpHeaders(result.httpHeaders, ExtractLooseHeaders(raw.headers))
    if raw.subtitles <> invalid and type(raw.subtitles) = "roArray"
        for each subTrack in raw.subtitles
            if subTrack <> invalid and type(subTrack) = "roAssociativeArray" and subTrack.url <> invalid
                subtitleUrl = AddonHttpUrl(subTrack.url)
                if subtitleUrl = "" then continue for
                track = {
                    url: subtitleUrl
                    id: AddonStringText(subTrack.id)
                    language: ""
                    label: ""
                    codec: ""
                }
                track.language = AddonScalarText(subTrack.lang)
                if track.language = "" then track.language = AddonScalarText(subTrack.language)
                I18n_Set(track, "label", AddonScalarText(subTrack.label))
                if track.label = "" then I18n_Set(track, "label", track.language)
                track.codec = AddonSubtitleFormatHint(subTrack)
                if track.codec = "" then track.codec = DetectSubtitleFormat(track.url)
                result.subtitles.Push(track)
            end if
        end for
    end if
    drmSystem = AddonStreamDrmSystem(raw)
    if result.kind = "http" and drmSystem <> ""
        result.kind = "drm"
        result.playable = false
        result.unsupportedReason = "drm-license-required"
        result.drmSystem = drmSystem
    end if
    ' Request headers have no meaning without an HTTP player URL. Response
    ' headers are retained as metadata and never sent as request headers.
    if result.url = "" then result.httpHeaders = []
    return result
end function

function AddonTextHasControls(value as string) as boolean
    for i = 1 to Len(value)
        code = Asc(Mid(value, i, 1))
        if code < 32 or code = 127 then return true
    end for
    return false
end function

function AddonHttpUrl(raw as dynamic) as string
    value = AddonStringText(raw).Trim()
    if value = "" or AddonTextHasControls(value) then return ""
    pattern = CreateObject("roRegex", "^https?://[^/?# ]+([/?#]|$)", "i")
    if not pattern.IsMatch(value) then return ""
    return value
end function

function AddonStreamFormatHint(record as dynamic) as string
    if Type(record) <> "roAssociativeArray" then return ""
    for each field in ["streamFormat", "format", "mimeType", "contentType"]
        value = AddonStringText(record[field])
        if value = "" then continue for
        value = LCase(value.Trim())
        separator = Instr(1, value, ";")
        if separator > 0 then value = Left(value, separator - 1).Trim()
        if value = "hls" or value = "m3u8" or value = "application/vnd.apple.mpegurl" or value = "application/x-mpegurl" or value = "audio/mpegurl" or value = "audio/x-mpegurl" then return "hls"
        if value = "dash" or value = "mpd" or value = "application/dash+xml" then return "dash"
        if value = "mp4" or value = "m4v" or value = "mov" or value = "video/mp4" or value = "video/quicktime" then return "mp4"
        if value = "mkv" or value = "matroska" or value = "video/x-matroska" then return "mkv"
    end for
    return ""
end function

function AddonFormatFromHeaders(headers as dynamic) as string
    if Type(headers) <> "roArray" then return ""
    for each header in headers
        line = AddonStringText(header)
        separator = Instr(1, line, ":")
        if separator <= 1 then continue for
        if LCase(Left(line, separator - 1).Trim()) = "content-type" then return AddonStreamFormatHint({ contentType: Mid(line, separator + 1) })
    end for
    return ""
end function

function AddonSubtitleFormatHint(track as dynamic) as string
    if Type(track) <> "roAssociativeArray" then return ""
    for each field in ["codec", "format", "mimeType", "contentType"]
        value = LCase(AddonStringText(track[field]).Trim())
        separator = Instr(1, value, ";")
        if separator > 0 then value = Left(value, separator - 1).Trim()
        if value = "srt" or value = "subrip" or value = "application/x-subrip" then return "srt"
        if value = "vtt" or value = "webvtt" or value = "text/vtt" then return "webvtt"
        if value = "ttml" or value = "dfxp" or value = "application/ttml+xml" then return "ttml"
        if value = "ass" or value = "ssa" then return value
    end for
    return ""
end function

' Only explicit DRM properties classify encryption. Provider titles, URL
' filenames and notWebReady are never treated as evidence of DRM.
function AddonStreamDrmSystem(raw as dynamic) as string
    if Type(raw) <> "roAssociativeArray" then return ""
    for each record in [raw, raw.behaviorHints]
        if Type(record) <> "roAssociativeArray" then continue for
        candidates = [record.drm, record.drmType, record.keySystem, record.licenseType]
        if Type(record.drm) = "roAssociativeArray"
            candidates.Push(record.drm.keySystem)
            candidates.Push(record.drm.type)
            candidates.Push(record.drm.system)
        else if Type(record.drm) = "Boolean" or Type(record.drm) = "roBoolean"
            if record.drm = true then return "unspecified"
        end if
        for each candidate in candidates
            name = LCase(AddonStringText(candidate).Trim())
            if name = "widevine" or name = "com.widevine.alpha" then return "widevine"
            if name = "playready" or name = "com.microsoft.playready" then return "playready"
            if name = "fairplay" or name = "com.apple.fps" or name = "com.apple.fps.1_0" then return "fairplay"
            if name = "clearkey" or name = "org.w3.clearkey" then return "clearkey"
        end for
    end for
    return ""
end function

'-------------------------------------------------------------------------------
' ExtractProxyHeaders
'-------------------------------------------------------------------------------
function ExtractProxyHeaders(behaviorHints as dynamic) as object
    headers = []
    if behaviorHints = invalid or type(behaviorHints) <> "roAssociativeArray" then
        return headers
    end if
    if behaviorHints.proxyHeaders = invalid or type(behaviorHints.proxyHeaders) <> "roAssociativeArray" then
        return headers
    end if
    proxyHeaders = behaviorHints.proxyHeaders
    if proxyHeaders.request = invalid or type(proxyHeaders.request) <> "roAssociativeArray" then
        return headers
    end if
    for each headerName in proxyHeaders.request
        headerValue = proxyHeaders.request[headerName]
        if headerName <> invalid and headerValue <> invalid
            cleanName = AddonScalarText(headerName)
            cleanValue = AddonScalarText(headerValue)
            cleanLine = NormalizeHttpHeaderLine(cleanName + ":" + cleanValue)
            if cleanLine <> "" then headers.Push(cleanLine)
        end if
    end for
    return headers
end function

'-------------------------------------------------------------------------------
' ExtractLooseHeaders
'-------------------------------------------------------------------------------
function ExtractLooseHeaders(rawHeaders as dynamic) as object
    headers = []
    if rawHeaders = invalid then
        return headers
    end if
    if Type(rawHeaders) = "roAssociativeArray"
        for each headerName in rawHeaders
            headerValue = rawHeaders[headerName]
            if headerName = invalid or headerValue = invalid then
                continue for
            end if
            cleanName = AddonScalarText(headerName).Trim()
            cleanValue = AddonScalarText(headerValue).Trim()
            cleanLine = NormalizeHttpHeaderLine(cleanName + ":" + cleanValue)
            if cleanLine <> "" then headers.Push(cleanLine)
        end for
    else if Type(rawHeaders) = "roArray"
        for each headerLine in rawHeaders
            if Instr(1, AddonStringText(headerLine), ":") > 1
                cleanLine = NormalizeHttpHeaderLine(AddonStringText(headerLine))
                if cleanLine <> "" then headers.Push(cleanLine)
            end if
        end for
    end if
    return headers
end function

' Validate both manifest dictionaries and preformatted header arrays before
' passing them to Roku Video. Never permit line breaks or reserved headers.
function NormalizeHttpHeaderLine(rawLine as string) as string
    if AddonTextHasControls(rawLine) then return ""
    separator = Instr(1, rawLine, ":")
    if separator <= 1 then return ""
    name = Left(rawLine, separator - 1).Trim()
    value = Mid(rawLine, separator + 1).Trim()
    tokenPattern = CreateObject("roRegex", "^[!#$%&'*+.^_`|~0-9A-Za-z-]+$", "")
    if name = "" or value = "" or not tokenPattern.IsMatch(name) or Left(LCase(name), 16) = "x-roku-reserved-" then return ""
    return name + ":" + value
end function

'-------------------------------------------------------------------------------
' MergeHttpHeaders
'-------------------------------------------------------------------------------
function MergeHttpHeaders(first as dynamic, second as dynamic) as object
    output = []
    seen = {}
    sources = [
        first
        second
    ]
    for each source in sources
        if source = invalid or Type(source) <> "roArray" then
            continue for
        end if
        for each headerLine in source
            if headerLine = invalid then
                continue for
            end if
            text = NormalizeHttpHeaderLine(AddonStringText(headerLine))
            separator = Instr(1, text, ":")
            if separator <= 1 then
                continue for
            end if
            headerName = LCase(Left(text, separator - 1).Trim())
            if headerName = "" or seen[headerName] <> invalid then
                continue for
            end if
            seen[headerName] = true
            output.Push(text)
        end for
    end for
    return output
end function

'-------------------------------------------------------------------------------
' DetectStreamFormat
'-------------------------------------------------------------------------------
function DetectStreamFormat(streamValue as string) as string
    lowerValue = LCase(streamValue)
    cutPosition = 0
    queryPosition = Instr(1, lowerValue, "?")
    fragmentPosition = Instr(1, lowerValue, "#")
    if queryPosition > 0 then
        cutPosition = queryPosition
    end if
    if fragmentPosition > 0 and (cutPosition = 0 or fragmentPosition < cutPosition)
        cutPosition = fragmentPosition
    end if
    if cutPosition > 0 then
        lowerValue = Left(lowerValue, cutPosition - 1)
    end if
    if Len(lowerValue) >= 5 and Right(lowerValue, 5) = ".m3u8" then
        return "hls"
    end if
    if Len(lowerValue) >= 4 and Right(lowerValue, 4) = ".mpd" then
        return "dash"
    end if
    if Len(lowerValue) >= 4 and Right(lowerValue, 4) = ".mp4" then
        return "mp4"
    end if
    if Len(lowerValue) >= 4 and Right(lowerValue, 4) = ".m4v" then
        return "mp4"
    end if
    if Len(lowerValue) >= 4 and Right(lowerValue, 4) = ".mov" then
        return "mp4"
    end if
    if Len(lowerValue) >= 4 and Right(lowerValue, 4) = ".mkv" then
        return "mkv"
    end if
    return ""
end function

'-------------------------------------------------------------------------------
' DetectSubtitleFormat
'-------------------------------------------------------------------------------
function DetectSubtitleFormat(subtitleUrl as string) as string
    lowerValue = LCase(subtitleUrl)
    cutPosition = 0
    queryPosition = Instr(1, lowerValue, "?")
    fragmentPosition = Instr(1, lowerValue, "#")
    if queryPosition > 0 then
        cutPosition = queryPosition
    end if
    if fragmentPosition > 0 and (cutPosition = 0 or fragmentPosition < cutPosition) then
        cutPosition = fragmentPosition
    end if
    if cutPosition > 0 then
        lowerValue = Left(lowerValue, cutPosition - 1)
    end if
    if Len(lowerValue) >= 4 and Right(lowerValue, 4) = ".srt" then
        return "srt"
    end if
    if Len(lowerValue) >= 4 and Right(lowerValue, 4) = ".vtt" then
        return "webvtt"
    end if
    if Len(lowerValue) >= 5 and Right(lowerValue, 5) = ".ttml" then
        return "ttml"
    end if
    if Len(lowerValue) >= 5 and Right(lowerValue, 5) = ".dfxp" then
        return "ttml"
    end if
    if Len(lowerValue) >= 4 and Right(lowerValue, 4) = ".ass" then
        return "ass"
    end if
    if Len(lowerValue) >= 4 and Right(lowerValue, 4) = ".ssa" then
        return "ssa"
    end if
    return "srt"
end function
' ---------------------------------------------------------------------------
' PC Addon Sync
' ---------------------------------------------------------------------------

'-------------------------------------------------------------------------------
' NormalizePcServerUrl
'-------------------------------------------------------------------------------
function NormalizePcServerUrl(raw as dynamic) as string
    if raw = invalid then
        return ""
    end if
    value = raw.ToStr().Trim()
    if value = "" then
        return ""
    end if
    if Left(LCase(value), 7) <> "http://" and Left(LCase(value), 8) <> "https://"
        value = "http://" + value
    end if
    while Len(value) > 0 and Right(value, 1) = "/"
        value = Left(value, Len(value) - 1)
    end while
    return value
end function

'-------------------------------------------------------------------------------
' LoadPcSyncServer
'-------------------------------------------------------------------------------
function LoadPcSyncServer() as string
    section = CreateObject("roRegistrySection", "StremioRoku")
    raw = section.Read("pcSyncServer")
    if raw = invalid then
        return ""
    end if
    return NormalizePcServerUrl(raw)
end function

'-------------------------------------------------------------------------------
' SavePcSyncServer
'-------------------------------------------------------------------------------
sub SavePcSyncServer(serverUrl as string)
    section = CreateObject("roRegistrySection", "StremioRoku")
    value = NormalizePcServerUrl(serverUrl)
    if value = ""
        section.Delete("pcSyncServer")
    else
        section.Write("pcSyncServer", value)
    end if
    section.Flush()
end sub
' ---------------------------------------------------------------------------
' Local library + playback progress
' ---------------------------------------------------------------------------

'-------------------------------------------------------------------------------
' LoadLibraryItems
'-------------------------------------------------------------------------------
function LoadLibraryItems() as object
    section = LocalAccountStore_DataSection(GetStremioProfileId())
    raw = section.Read("library")
    if raw = invalid or raw = "" then
        return []
    end if
    parsed = ParseJson(raw)
    if parsed = invalid or type(parsed) <> "roArray" then
        return []
    end if
    return parsed
end function

'-------------------------------------------------------------------------------
' SaveLibraryItems
'-------------------------------------------------------------------------------
sub SaveLibraryItems(items as object)
    if items = invalid then
        items = []
    end if
    while items.Count() > 20
        items.Delete(items.Count() - 1)
    end while
    jsonText = FormatJson(items)
    while Len(jsonText) > 10000 and items.Count() > 1
        items.Delete(items.Count() - 1)
        jsonText = FormatJson(items)
    end while
    section = LocalAccountStore_DataSection(GetStremioProfileId())
    if section.Write("library", jsonText) then
        section.Flush()
    end if
end sub

'-------------------------------------------------------------------------------
' CompactMediaItem
'-------------------------------------------------------------------------------
function CompactMediaItem(item as dynamic) as dynamic
    if item = invalid or Type(item) <> "roAssociativeArray" then
        return invalid
    end if
    out = {
        id: ""
        type: ""
        name: "Conteúdo"
        poster: ""
        background: ""
        description: ""
    }
    out.id = AddonScalarText(item.id)
    out.type = AddonScalarText(item.type)
    if item.name <> invalid
        out.name = AddonScalarText(item.name, "Conteúdo")
        if Len(out.name) > 120 then
            out.name = Left(out.name, 120)
        end if
    end if
    if item.poster <> invalid
        poster = AddonStringText(item.poster)
        if Len(poster) <= 700 then
            out.poster = poster
        end if
    end if
    if item.background <> invalid
        background = AddonStringText(item.background)
        if Len(background) <= 700 then
            out.background = background
        end if
    end if
    if item.description <> invalid
        I18n_Set(out, "description", AddonScalarText(item.description))
        if Len(out.description) > 180 then
            I18n_Set(out, "description", Left(out.description, 180))
        end if
    end if
    if out.id = "" or out.type = "" then
        return invalid
    end if
    playbackId = AddonStringText(item.playbackId)
    if playbackId <> "" then out.playbackId = playbackId
    if Type(item.isLive) = "Boolean" or Type(item.isLive) = "roBoolean" then out.isLive = item.isLive
    if LCase(out.type) = "tv" and item.iptvStreamUrl <> invalid
        streamUrl = AddonHttpUrl(item.iptvStreamUrl)
        if Len(streamUrl) <= 2048 then out.iptvStreamUrl = streamUrl
    end if
    return out
end function

'-------------------------------------------------------------------------------
' ToggleLibraryItem
'-------------------------------------------------------------------------------
function ToggleLibraryItem(item as dynamic) as boolean
    compact = CompactMediaItem(item)
    if compact = invalid then
        return false
    end if
    items = LoadLibraryItems()
    key = compact.type + ":" + compact.id
    kept = []
    removed = false
    for each existing in items
        existingKey = ""
        if Type(existing) = "roAssociativeArray" and AddonScalarText(existing.id) <> "" and AddonScalarText(existing.type) <> ""
            existingKey = AddonScalarText(existing.type) + ":" + AddonScalarText(existing.id)
        end if
        if existingKey = key
            removed = true
        else
            kept.Push(existing)
        end if
    end for
    if removed
        SaveLibraryItems(kept)
        return false
    end if
    kept.Unshift(compact)
    while kept.Count() > 20
        kept.Delete(kept.Count() - 1)
    end while
    SaveLibraryItems(kept)
    return true
end function

'-------------------------------------------------------------------------------
' IsLibraryMediaId
'-------------------------------------------------------------------------------
function IsLibraryMediaId(mediaId as string) as boolean
    if mediaId = "" then
        return false
    end if
    for each item in LoadLibraryItems()
        if Type(item) = "roAssociativeArray"
            if AddonScalarText(item.id) = mediaId then return true
        end if
    end for
    return false
end function

'-------------------------------------------------------------------------------
' LoadWatchedIds
'-------------------------------------------------------------------------------
function LoadWatchedIds() as object
    section = LocalAccountStore_DataSection(GetStremioProfileId())
    raw = section.Read("watchedIds")
    if raw = invalid or raw = "" then
        return []
    end if
    parsed = ParseJson(raw)
    if parsed = invalid or Type(parsed) <> "roArray" then
        return []
    end if
    return parsed
end function

'-------------------------------------------------------------------------------
' SaveWatchedIds
'-------------------------------------------------------------------------------
sub SaveWatchedIds(ids as object)
    if ids = invalid then
        ids = []
    end if
    while ids.Count() > 120
        ids.Delete(ids.Count() - 1)
    end while
    jsonText = FormatJson(ids)
    while Len(jsonText) > 9000 and ids.Count() > 1
        ids.Delete(ids.Count() - 1)
        jsonText = FormatJson(ids)
    end while
    section = LocalAccountStore_DataSection(GetStremioProfileId())
    if section.Write("watchedIds", jsonText) then
        section.Flush()
    end if
end sub

'-------------------------------------------------------------------------------
' IsWatched
'-------------------------------------------------------------------------------
function IsWatched(mediaId as string) as boolean
    if mediaId = "" then
        return false
    end if
    for each value in LoadWatchedIds()
        if AddonScalarText(value) = mediaId then
            return true
        end if
    end for
    return false
end function

'-------------------------------------------------------------------------------
' SetWatched
'-------------------------------------------------------------------------------
sub SetWatched(mediaId as string, watched as boolean)
    if mediaId = "" then
        return
    end if
    kept = []
    for each value in LoadWatchedIds()
        if AddonScalarText(value) <> mediaId then
            kept.Push(value)
        end if
    end for
    if watched then
        kept.Unshift(mediaId)
    end if
    SaveWatchedIds(kept)
end sub

'-------------------------------------------------------------------------------
' DeleteWatchProgressForRoot
'-------------------------------------------------------------------------------
sub DeleteWatchProgressForRoot(rootId as string)
    if rootId = "" then
        return
    end if
    kept = []
    for each entry in LoadWatchProgressItems()
        if entry = invalid or entry.rootId = invalid or entry.rootId.ToStr() <> rootId then
            kept.Push(entry)
        end if
    end for
    SaveWatchProgressItems(kept)
end sub

'-------------------------------------------------------------------------------
' LoadWatchProgressItems
'-------------------------------------------------------------------------------
function LoadWatchProgressItems() as object
    section = LocalAccountStore_DataSection(GetStremioProfileId())
    raw = section.Read("watchProgress")
    if raw = invalid or raw = "" then
        return []
    end if
    parsed = ParseJson(raw)
    if parsed = invalid or type(parsed) <> "roArray" then
        return []
    end if
    return parsed
end function

'-------------------------------------------------------------------------------
' SaveWatchProgress
'-------------------------------------------------------------------------------
sub SaveWatchProgress(mediaId as string, rootMedia as dynamic, title as string, position as integer, duration as integer, context = invalid as dynamic, completed = false as boolean)
    if mediaId = "" or rootMedia = invalid or position < 10 then
        return
    end if
    compact = CompactMediaItem(rootMedia)
    if compact = invalid then
        return
    end if
    mediaType = LCase(compact.type)
    if mediaType <> "movie" and mediaType <> "series" then
        return
    end if
    items = LoadWatchProgressItems()
    kept = []
    for each existing in items
        if existing = invalid or existing.mediaId = invalid or existing.mediaId.ToStr() <> mediaId
            kept.Push(existing)
        end if
    end for
    if completed
        SetWatched(mediaId, true)
        ' A finished episode must not reveal an older stale resume point from
        ' the same series. Clear unfinished progress for this root; the series
        ' screen will advance to the first unplayed episode.
        completedKept = []
        for each existing in kept
            if existing = invalid or existing.rootId = invalid or existing.rootId.ToStr() <> compact.id
                completedKept.Push(existing)
            end if
        end for
        SaveWatchProgressItems(completedKept)
        return
    end if
    now = CreateObject("roDateTime")
    seasonNumber = 0
    episodeNumber = 0
    if context <> invalid and Type(context) = "roAssociativeArray"
        if context.ParentIndexNumber <> invalid then
            seasonNumber = Int(context.ParentIndexNumber)
        end if
        if context.IndexNumber <> invalid then
            episodeNumber = Int(context.IndexNumber)
        end if
    end if
    entry = {
        mediaId: mediaId
        rootId: compact.id
        media: compact
        title: title
        position: position
        duration: duration
        season: seasonNumber
        episode: episodeNumber
        updated: now.AsSeconds()
    }
    kept.Unshift(entry)
    while kept.Count() > 15
        kept.Delete(kept.Count() - 1)
    end while
    SaveWatchProgressItems(kept)
end sub

'-------------------------------------------------------------------------------
' SaveWatchProgressItems
'-------------------------------------------------------------------------------
sub SaveWatchProgressItems(items as object)
    if items = invalid then
        items = []
    end if
    while items.Count() > 15
        items.Delete(items.Count() - 1)
    end while
    jsonText = FormatJson(items)
    while Len(jsonText) > 10000 and items.Count() > 1
        items.Delete(items.Count() - 1)
        jsonText = FormatJson(items)
    end while
    section = LocalAccountStore_DataSection(GetStremioProfileId())
    if section.Write("watchProgress", jsonText) then
        section.Flush()
    end if
end sub

'-------------------------------------------------------------------------------
' FindWatchProgress
'-------------------------------------------------------------------------------
function FindWatchProgress(mediaId as string) as dynamic
    if mediaId = "" then
        return invalid
    end if
    for each entry in LoadWatchProgressItems()
        if entry <> invalid and entry.mediaId <> invalid and entry.mediaId.ToStr() = mediaId then
            return entry
        end if
    end for
    return invalid
end function

'-------------------------------------------------------------------------------
' BindStremioProfile
'-------------------------------------------------------------------------------
sub BindStremioProfile(request as dynamic)
    id = ""
    if request <> invalid then
        id = Format_SafeString(request.userId, "")
    end if
    if id = "" then
        id = LocalAccountStore_ActiveId()
    end if
    m.stremioProfileScope = {
        id: id
    }
end sub

'-------------------------------------------------------------------------------
' GetStremioProfileId
'-------------------------------------------------------------------------------
function GetStremioProfileId() as string
    if m.stremioProfileScope <> invalid then
        return m.stremioProfileScope.id
    end if
    return LocalAccountStore_ActiveId()
end function

'-------------------------------------------------------------------------------
' LatestWatchProgressForRoot
'-------------------------------------------------------------------------------
function LatestWatchProgressForRoot(rootId as string) as dynamic
    if rootId = "" then
        return invalid
    end if
    for each entry in LoadWatchProgressItems()
        if entry <> invalid and entry.rootId <> invalid and entry.rootId.ToStr() = rootId then
            return entry
        end if
    end for
    return invalid
end function

'-------------------------------------------------------------------------------
' DeleteWatchProgress
'-------------------------------------------------------------------------------
sub DeleteWatchProgress(mediaId as string)
    if mediaId = "" then
        return
    end if
    kept = []
    for each entry in LoadWatchProgressItems()
        if entry = invalid or entry.mediaId = invalid or entry.mediaId.ToStr() <> mediaId then
            kept.Push(entry)
        end if
    end for
    SaveWatchProgressItems(kept)
end sub

'-------------------------------------------------------------------------------
' ContinueWatchingMediaItems
'-------------------------------------------------------------------------------
function ContinueWatchingMediaItems() as object
    out = []
    roots = {}
    for each entry in LoadWatchProgressItems()
        if entry <> invalid and entry.media <> invalid and entry.rootId <> invalid
            rootKey = entry.rootId.ToStr()
            if roots[rootKey] = invalid
                roots[rootKey] = true
                out.Push(entry.media)
            end if
        end if
        if out.Count() >= 12 then
            exit for
        end if
    end for
    return out
end function

' Browser-managed IPTV playlists use separate registry slots. The original
' function IPTVBrowser_CustomSources() as object
    section = CreateObject("roRegistrySection", "StremioRoku")
    sources = []
    
    ' Add your specific M3U playlist as a default source
    sources.Push({ 
        id: "stremio:iptv:custom_gott", 
        name: "Gott Smart IPTV", 
        url: "http://gott-smart.net:80/get.php?username=X5STVH8KCV25445&password=biFly6x6iL&type=m3u_plus" 
    })

    for slot = 1 to 8
        suffix = slot.ToStr()
        url = Format_SafeString(section.Read("iptv_browser_" + suffix + "_url"), "")
        if url <> ""
            name = Format_SafeString(section.Read("iptv_browser_" + suffix + "_name"), "")
            if name = "" then name = I18n_T("Minha lista ") + suffix
            sources.Push({ id: "stremio:iptv:user" + suffix, name: name, url: url })
        end if
    next ' Added missing loop closer for standard BrightScript syntax

    end for
    return sources
end function

function IPTVBrowser_Lists() as object
    output = []
    section = CreateObject("roRegistrySection", "StremioRoku")
    oldUrl = Format_SafeString(section.Read("iptv_playlist_url"), "")
    if oldUrl <> "" then output.Push({ id: "stremio:iptv", name: "Minha lista antiga", url: oldUrl })
    for each source in IPTVBrowser_CustomSources()
        output.Push(source)
    end for
    return output
end function

function IPTVBrowser_Add(rawUrl as string) as object
    url = rawUrl.Trim()
    lowerUrl = LCase(url)
    hostPattern = CreateObject("roRegex", "^https?://[^/?# ]+([/?#]|$)", "")
    if Len(url) = 0 or Len(url) > 2048 or Instr(1, url, Chr(10)) > 0 or Instr(1, url, Chr(13)) > 0 or Instr(1, url, Chr(9)) > 0 or Instr(1, url, " ") > 0 or not hostPattern.IsMatch(lowerUrl)
        return { ok: false, error: I18n_T("Use um link HTTP(S) valido de lista M3U.") }
    end if
    section = CreateObject("roRegistrySection", "StremioRoku")
    if Format_SafeString(section.Read("iptv_playlist_url"), "") = url
        return { ok: true, name: "Minha lista antiga", duplicate: true }
    end if
    freeSlot = 0
    for slot = 1 to 8
        suffix = slot.ToStr()
        savedUrl = Format_SafeString(section.Read("iptv_browser_" + suffix + "_url"), "")
        if savedUrl = url
            return { ok: true, name: "Minha lista " + suffix, duplicate: true }
        end if
        if savedUrl = "" and freeSlot = 0 then freeSlot = slot
    end for
    if freeSlot = 0 then return { ok: false, error: I18n_T("Limite de 8 listas adicionais. Remova uma para continuar.") }
    suffix = freeSlot.ToStr()
    name = I18n_T("Minha lista ") + suffix
    if not section.Write("iptv_browser_" + suffix + "_url", url) then return { ok: false, error: I18n_T("Nao foi possivel salvar a lista.") }
    if not section.Write("iptv_browser_" + suffix + "_name", name) then return { ok: false, error: I18n_T("Nao foi possivel salvar a lista.") }
    if not section.Flush() then return { ok: false, error: I18n_T("Nao foi possivel salvar a lista.") }
    return { ok: true, name: name, id: "stremio:iptv:user" + suffix }
end function

function IPTVBrowser_Remove(id as string) as boolean
    section = CreateObject("roRegistrySection", "StremioRoku")
    if id = "stremio:iptv"
        if not section.Write("iptv_playlist_url", "") then return false
        return section.Flush()
    end if
    for slot = 1 to 8
        suffix = slot.ToStr()
        if id = "stremio:iptv:user" + suffix
            if not section.Write("iptv_browser_" + suffix + "_url", "") then return false
            if not section.Write("iptv_browser_" + suffix + "_name", "") then return false
            return section.Flush()
        end if
    end for
    return false
end function
