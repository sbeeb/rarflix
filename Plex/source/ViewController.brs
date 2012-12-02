'*
'* A controller for managing the stack of screens that have been displayed.
'* By centralizing this we can better support things like destroying and
'* recreating views and breadcrumbs. It also provides a single place that
'* can take an item and figure out which type of screen should be shown
'* so that logic doesn't have to be in each individual screen type.
'*

Function createViewController() As Object
    controller = CreateObject("roAssociativeArray")

    controller.breadcrumbs = CreateObject("roArray", 10, true)
    controller.screens = CreateObject("roArray", 10, true)

    controller.GlobalMessagePort = CreateObject("roMessagePort")

    controller.CreateScreenForItem = vcCreateScreenForItem
    controller.CreateTextInputScreen = vcCreateTextInputScreen
    controller.CreateEnumInputScreen = vcCreateEnumInputScreen
    controller.CreateMyPlexPinScreen = vcCreateMyPlexPinScreen

    controller.CreatePhotoPlayer = vcCreatePhotoPlayer
    controller.CreateVideoPlayer = vcCreateVideoPlayer

    controller.InitializeOtherScreen = vcInitializeOtherScreen
    controller.AssignScreenID = vcAssignScreenID
    controller.PushScreen = vcPushScreen
    controller.PopScreen = vcPopScreen

    controller.Show = vcShow
    controller.RefreshHomeScreen = vcRefreshHomeScreen
    controller.UpdateScreenProperties = vcUpdateScreenProperties
    controller.AddBreadcrumbs = vcAddBreadcrumbs

    controller.DestroyGlitchyScreens = vcDestroyGlitchyScreens

    controller.facade = CreateObject("roGridScreen")
    controller.facade.Show()

    controller.nextScreenId = 1
    controller.nextTimerId = 1

    controller.InitThemes = vcInitThemes
    controller.PushTheme = vcPushTheme
    controller.PopTheme = vcPopTheme
    controller.ApplyThemeAttrs = vcApplyThemeAttrs

    controller.InitThemes()

    controller.PendingRequests = {}
    controller.RequestsByScreen = {}
    controller.StartRequest = vcStartRequest
    controller.CancelRequests = vcCancelRequests

    controller.SocketListeners = {}
    controller.AddSocketListener = vcAddSocketListener

    controller.Timers = {}
    controller.TimersByScreen = {}
    controller.AddTimer = vcAddTimer

    InitWebServer(controller)

    ' Stuff the controller into the global object
    m.ViewController = controller
    controller.myplex = createMyPlexManager(controller)
    controller.AudioPlayer = createAudioPlayer(controller)

    return controller
End Function

Function GetViewController()
    return m.ViewController
End Function

Function GetMyPlexManager()
    return GetViewController().myplex
End Function

Function vcCreateScreenForItem(context, contextIndex, breadcrumbs, show=true) As Dynamic
    if type(context) = "roArray" then
        item = context[contextIndex]
    else
        item = context
    end if

    contentType = item.ContentType
    viewGroup = item.viewGroup
    if viewGroup = invalid then viewGroup = ""

    screen = CreateObject("roAssociativeArray")

    ' NOTE: We don't support switching between them as a preference, but
    ' the poster screen can be used anywhere the grid is used below. By
    ' default the poster screen will try to decide whether or not to
    ' include the filter bar that makes it more grid like, but it can
    ' be forced by setting screen.FilterMode = true.

    if contentType = "movie" OR contentType = "episode" then
        screen = createVideoSpringboardScreen(context, contextIndex, m)
    else if contentType = "clip" then
        screen = createVideoSpringboardScreen(context, contextIndex, m)
    else if contentType = "series" then
        if RegRead("use_grid_for_series", "preferences", "") <> "" then
            screen = createGridScreenForItem(item, m, "flat-16X9")
        else
            screen = createPosterScreen(item, m)
        end if
    else if contentType = "artist" then
        ' TODO: Poster, poster with filters, or grid?
        screen = createPosterScreen(item, m)
    else if contentType = "album" then
        screen = createPosterScreen(item, m)
        ' TODO: What style looks best here, episodic?
        screen.SetListStyle("flat-episodic", "zoom-to-fill")
    else if contentType = "audio" then
        screen = createAudioSpringboardScreen(context, contextIndex, m)
        if screen = invalid then return invalid
    else if contentType = "section" then
        RegWrite("lastMachineID", item.server.machineID)
        RegWrite("lastSectionKey", item.key)
        screen = createGridScreenForItem(item, m, "flat-movie")
    else if contentType = "photo" then
        if right(item.key, 8) = "children" then
            screen = createPosterScreen(item, m)
        else
            screen = createPhotoSpringboardScreen(context, contextIndex, m)
        end if
    else if contentType = "search" then
        screen = createSearchScreen(item, m)
    else if item.key = "/system/appstore" then
        screen = createGridScreenForItem(item, m, "flat-square")
    else if viewGroup = "Store:Info" then
        dialog = createPopupMenu(item)
        dialog.Show()
        return invalid
    else if viewGroup = "secondary" then
        screen = createPosterScreen(item, m)
    else if item.key = "globalprefs" then
        screen = createPreferencesScreen(m)
    else if item.key = "/channels/all" then
        ' Special case for all channels to force it into a special grid view
        screen = createGridScreen(m, "flat-square")
        names = ["Video Channels", "Music Channels", "Photo Channels"]
        keys = ["/video", "/music", "/photos"]
        fakeContainer = createFakePlexContainer(item.server, names, keys)
        screen.Loader = createPaginatedLoader(fakeContainer, 8, 25)
        screen.Loader.Listener = screen
        screen.Loader.Port = screen.Port
        screen.MessageHandler = screen.Loader
    else if item.searchTerm <> invalid AND item.server = invalid then
        screen = createGridScreen(m, "flat-square")
        screen.Loader = createSearchLoader(item.searchTerm)
        screen.Loader.Listener = screen
        screen.MessageHandler = screen.Loader
    else if item.settings = "1"
        screen = createSettingsScreen(item, m)
    else
        ' Where do we capture channel directory?
        Debug("Creating a default view for contentType=" + tostr(contentType) + ", viewGroup=" + tostr(viewGroup))
        screen = createPosterScreen(item, m)
    end if

    m.AddBreadcrumbs(screen, breadcrumbs)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Function vcCreateTextInputScreen(heading, breadcrumbs, show=true) As Dynamic
    screen = createKeyboardScreen(m)

    if heading <> invalid then
        screen.Screen.SetDisplayText(heading)
    end if

    m.AddBreadcrumbs(screen, breadcrumbs)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Function vcCreateEnumInputScreen(options, selected, heading, breadcrumbs, show=true) As Dynamic
    screen = createEnumScreen(options, selected, m)

    if heading <> invalid then
        screen.Screen.SetHeader(heading)
    end if

    m.AddBreadcrumbs(screen, breadcrumbs)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Function vcCreateMyPlexPinScreen(show=true)
    screen = createMyPlexPinScreen(m)

    m.AddBreadcrumbs(screen, invalid)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Function vcCreatePhotoPlayer(context, contextIndex=invalid, show=true)
    screen = createPhotoPlayerScreen(context, contextIndex, m)

    m.AddBreadcrumbs(screen, invalid)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Function vcCreateVideoPlayer(metadata, seekValue=0, directPlayOptions=0, show=true)
    screen = createVideoPlayerScreen(metadata, seekValue, directPlayOptions, m)

    m.AddBreadcrumbs(screen, invalid)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Sub vcInitializeOtherScreen(screen, breadcrumbs)
    m.AddBreadcrumbs(screen, breadcrumbs)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)
End Sub

Sub vcAssignScreenID(screen)
    if screen.ScreenID = invalid then
        screen.ScreenID = m.nextScreenId
        m.nextScreenId = m.nextScreenId + 1
    end if
End Sub

Sub vcPushScreen(screen)
    m.AssignScreenID(screen)
    Debug("Pushing screen " + tostr(screen.ScreenID) + " onto view controller stack - " + type(screen.Screen))
    m.screens.Push(screen)
End Sub

Sub vcPopScreen(screen)
    if screen.ScreenID = -1 then
        Debug("Popping home screen, cleaning up")

        while m.screens.Count() > 1
            m.PopScreen(m.screens.Peek())
        end while
        m.screens.Pop()

        m.Home = invalid
        return
    end if

    if screen.Cleanup <> invalid then screen.Cleanup()

    ' Try to clean up some potential circular references
    screen.MessageHandler = invalid
    screen.Listener = invalid
    if screen.Loader <> invalid then
        screen.Loader.Listener = invalid
        screen.Loader = invalid
    end if

    if screen.ScreenID = invalid OR m.screens.Peek().ScreenID = invalid OR screen.ScreenID <> m.screens.Peek().ScreenID then
        Debug("Trying to pop screen that doesn't match the top of our stack!")
        Return
    end if

    screenID = screen.ScreenID.tostr()

    Debug("Popping screen " + screenID + " and cleaning up " + tostr(screen.NumBreadcrumbs) + " breadcrumbs")
    m.screens.Pop()
    for i = 0 to screen.NumBreadcrumbs - 1
        m.breadcrumbs.Pop()
    next

    ' Clean up any requests initiated by this screen
    m.CancelRequests(screen.ScreenID)

    ' Clean up any timers initiated by this screen
    timers = m.TimersByScreen[screenID]
    if timers <> invalid then
        for each timerID in timers
            timer = m.Timers[timerID]
            timer.Active = false
            timer.Listener = invalid
            m.Timers.Delete(timerID)
        next
        m.TimersByScreen.Delete(screenID)
    end if

    ' Let the new top of the stack know that it's visible again.
    m.screens.Peek().Activate(screen)

    if m.screens.Count() = 0 then
        m.Home.CreateQueueRequests(true)
    end if
End Sub

Sub vcShow()
    m.Home = createHomeScreen(m)
    m.Home.ScreenID = -1
    m.InitializeOtherScreen(m.Home, invalid)
    m.Home.Show()

    Debug("Starting global message loop")

    timeout = 0
    while m.screens.Count() > 0
        m.WebServer.prewait()
        msg = wait(timeout, m.GlobalMessagePort)
        if msg <> invalid then
            ' Printing debug information about every message may be overkill
            ' regardless, but note that URL events don't play by the same rules,
            ' and there's no ifEvent interface to check for. Sigh.
            'if GetInterface(msg, "ifUrlEvent") = invalid AND GetInterface(msg, "ifSocketEvent") = invalid then
                'Debug("Processing " + type(msg) + " (top of stack " + type(m.screens.Peek().Screen) + "): " + tostr(msg.GetType()) + ", " + tostr(msg.GetIndex()) + ", " + tostr(msg.GetMessage()))
            'end if

            for i = m.screens.Count() - 1 to 0 step -1
                if m.screens[i].HandleMessage(msg) then exit for
            end for

            ' Process URL events. Look up the request context and call a
            ' function on the listener.
            if type(msg) = "roUrlEvent" AND msg.GetInt() = 1 then
                id = msg.GetSourceIdentity().tostr()
                requestContext = m.PendingRequests[id]
                if requestContext <> invalid then
                    m.PendingRequests.Delete(id)
                    requestContext.Listener.OnUrlEvent(msg, requestContext)
                end if
            else if type(msg) = "roSocketEvent" then
                listener = m.SocketListeners[msg.getSocketID().tostr()]
                if listener <> invalid then
                    listener.OnSocketEvent(msg)
                else
                    ' Assume it was for the web server (it won't hurt if it wasn't)
                    m.WebServer.postwait()
                end if
            else if type(msg) = "roAudioPlayerEvent" then
                m.AudioPlayer.HandleMessage(msg)
            end if
        end if

        ' Check for any expired timers
        timeout = 0
        for each timerID in m.Timers
            timer = m.Timers[timerID]
            if timer.IsExpired() then
                timer.Listener.OnTimerExpired(timer)
            end if

            ' Make sure we set a timeout on the wait so we'll catch the next timer
            remaining = timer.RemainingMillis()
            if remaining > 0 AND (timeout = 0 OR remaining < timeout) then
                timeout = remaining
            end if
        next
    end while

    Debug("Finished global message loop")
End Sub

Sub vcRefreshHomeScreen()
    while m.screens.Count() > 1
        m.PopScreen(m.screens.Peek())
    end while

    m.Home.Refresh()
End Sub

Sub vcAddBreadcrumbs(screen, breadcrumbs)
    ' Add the breadcrumbs to our list and set them for the current screen.
    ' If the current screen specified invalid for the breadcrubms then it
    ' doesn't want any breadcrumbs to be shown. If it specified an empty
    ' array, then the current breadcrumbs will be shown again.
    screenType = type(screen.Screen)
    if breadcrumbs = invalid then
        screen.NumBreadcrumbs = 0
        return
    end if

    ' Special case for springboard screens, don't show the current title
    ' in the breadcrumbs.
    if screenType = "roSpringboardScreen" AND breadcrumbs.Count() > 0 then
        breadcrumbs.Pop()
    end if

    if breadcrumbs.Count() = 0 AND m.breadcrumbs.Count() > 0 then
        count = m.breadcrumbs.Count()
        if count >= 2 then
            breadcrumbs = [m.breadcrumbs[count-2], m.breadcrumbs[count-1]]
        else
            breadcrumbs = m.breadcrumbs[0]
        end if

        m.breadcrumbs.Append(breadcrumbs)
        screen.NumBreadcrumbs = breadcrumbs.Count()
    else
        for each b in breadcrumbs
            m.breadcrumbs.Push(tostr(b))
        next
        screen.NumBreadcrumbs = breadcrumbs.Count()
    end if
End Sub

Sub vcUpdateScreenProperties(screen)
    ' Make sure that metadata requests from the screen carry an auth token.
    if GetInterface(screen.Screen, "ifHttpAgent") <> invalid AND screen.Item <> invalid AND screen.Item.server <> invalid AND screen.Item.server.AccessToken <> invalid then
        screen.Screen.AddHeader("X-Plex-Token", screen.Item.server.AccessToken)
    end if

    if screen.NumBreadcrumbs <> 0 then
        count = m.breadcrumbs.Count()
        if count >= 2 then
            enableBreadcrumbs = true
            bread1 = m.breadcrumbs[count-2]
            bread2 = m.breadcrumbs[count-1]
        else if count = 1 then
            enableBreadcrumbs = true
            bread1 = ""
            bread2 = m.breadcrumbs[0]
        else
            enableBreadcrumbs = false
        end if
    else
        enableBreadcrumbs = false
    end if

    screenType = type(screen.Screen)
    ' Sigh, different screen types don't support breadcrumbs with the same functions
    if screenType = "roGridScreen" OR screenType = "roPosterScreen" OR screenType = "roSpringboardScreen" then
        if enableBreadcrumbs then
            screen.Screen.SetBreadcrumbEnabled(true)
            screen.Screen.SetBreadcrumbText(bread1, bread2)
        else
            screen.Screen.SetBreadcrumbEnabled(false)
        end if
    else if screenType = "roSearchScreen" then
        if enableBreadcrumbs then
            screen.Screen.SetBreadcrumbText(bread1, bread2)
        end if
    else if screenType = "roListScreen" OR screenType = "roKeyboardScreen" OR screenType = "roParagraphScreen" then
        if enableBreadcrumbs then
            screen.Screen.SetTitle(bread2)
        end if
    else
        Debug("Not sure what to do with breadcrumbs on screen type: " + tostr(screenType))
    end if
End Sub

Sub vcInitThemes()
    m.ThemeStack = CreateObject("roList")
    m.ThemeApplyParams = CreateObject("roAssociativeArray")
    m.ThemeRevertParams = CreateObject("roAssociativeArray")
End Sub

Sub vcPushTheme(name)
    if NOT m.ThemeApplyParams.DoesExist(name) then return

    if name <> m.ThemeStack.GetTail() then
        m.ApplyThemeAttrs(m.ThemeApplyParams[name])
    end if

    m.ThemeStack.AddTail(name)
End Sub

Sub vcPopTheme()
    name = m.ThemeStack.RemoveTail()

    if name <> m.ThemeStack.GetTail() then
        m.ApplyThemeAttrs(m.ThemeRevertParams[name])
        m.ApplyThemeAttrs(m.ThemeApplyParams[m.ThemeStack.GetTail()])
    end if
End Sub

Sub vcApplyThemeAttrs(attrs)
    app = CreateObject("roAppManager")
    for each attr in attrs
        if attrs[attr] <> invalid then
            app.SetThemeAttribute(attr, attrs[attr])
        else
            app.ClearThemeAttribute(attr)
        end if
    next
End Sub

Sub vcDestroyGlitchyScreens()
    for each screen in m.screens
        if screen.DestroyAndRecreate <> invalid then
            Debug("Destroying screen " + tostr(screen.ScreenID) + " to work around glitch")
            screen.DestroyAndRecreate()
        end if
    next
End Sub

Function vcStartRequest(request, listener, context, body=invalid) As Boolean
    request.SetPort(m.GlobalMessagePort)
    context.Listener = listener
    context.Request = request

    if body = invalid then
        started = request.AsyncGetToString()
    else
        started = request.AsyncPostFromString(body)
    end if

    if started then
        id = request.GetIdentity().tostr()
        m.PendingRequests[id] = context
        screenID = listener.ScreenID.tostr()
        if NOT m.RequestsByScreen.DoesExist(screenID) then
            m.RequestsByScreen[screenID] = []
        end if
        m.RequestsByScreen[screenID].Push(id)
        return true
    else
        return false
    end if
End Function

Sub vcCancelRequests(screenID)
    requests = m.RequestsByScreen[screenID.tostr()]
    if requests <> invalid then
        for each requestID in requests
            request = m.PendingRequests[requestID]
            if request <> invalid then request.Request.AsyncCancel()
            m.PendingRequests.Delete(requestID)
        next
        m.RequestsByScreen.Delete(screenID.tostr())
    end if
End Sub

Sub vcAddSocketListener(socket, listener)
    m.SocketListeners[socket.GetID().tostr()] = listener
End Sub

Sub vcAddTimer(timer, listener)
    timer.ID = m.nextTimerId.tostr()
    m.nextTimerId = m.NextTimerId + 1
    timer.Listener = listener
    m.Timers[timer.ID] = timer

    screenID = listener.ScreenID.tostr()
    if NOT m.TimersByScreen.DoesExist(screenID) then
        m.TimersByScreen[screenID] = []
    end if
    m.TimersByScreen[screenID].Push(timer.ID)
End Sub

Sub InitWebServer(vc)
    ' Initialize some globals for the web server
    globals = CreateObject("roAssociativeArray")
    globals.pkgname = "Plex/Roku"
    globals.maxRequestLength = 4000
    globals.idletime = 60
    globals.wwwroot = "tmp:/"
    globals.index_name = "index.html"
    globals.serverName = "Plex/Roku"
    AddGlobals(globals)
    MimeType()
    HttpTitle()
    ClassReply().AddHandler("/logs", ProcessLogsRequest)

    vc.WebServer = InitServer({msgPort: vc.GlobalMessagePort, port: 8324})
End Sub
