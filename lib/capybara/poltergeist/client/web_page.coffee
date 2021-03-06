class Poltergeist.WebPage
  @CALLBACKS = ['onAlert', 'onConsoleMessage', 'onLoadFinished', 'onInitialized',
                'onLoadStarted', 'onResourceRequested', 'onResourceReceived',
                'onError', 'onNavigationRequested', 'onUrlChanged', 'onPageCreated',
                'onConfirm', 'onPrompt']

  @DELEGATES = ['open', 'sendEvent', 'uploadFile', 'release', 'render']

  @COMMANDS  = ['currentUrl', 'find', 'nodeCall', 'documentSize']

  constructor: (@native) ->
    @native or= require('webpage').create()

    @_source         = ""
    @_errors         = []
    @_networkTraffic = {}
    @frames          = []
    @sub_pages       = {}

    for callback in WebPage.CALLBACKS
      this.bindCallback(callback)

    this.injectAgent()

  for command in @COMMANDS
    do (command) =>
      this.prototype[command] =
        (args...) -> this.runCommand(command, args)

  for delegate in @DELEGATES
    do (delegate) =>
      this.prototype[delegate] =
        -> @native[delegate].apply(@native, arguments)

  onInitializedNative: ->
    @_source = null
    this.injectAgent()
    this.setScrollPosition(left: 0, top: 0)

  injectAgent: ->
    if @native.evaluate(-> typeof __poltergeist) == "undefined"
      @native.injectJs("#{phantom.libraryPath}/agent.js")

  onConsoleMessageNative: (message) ->
    if message == '__DOMContentLoaded'
      @_source = @native.content
      false

  onLoadStartedNative: ->
    @requestId = @lastRequestId

  onLoadFinishedNative: ->
    @_source or= @native.content

  onConsoleMessage: (message) ->
    console.log(message)

  onErrorNative: (message, stack) ->
    stackString = message

    stack.forEach (frame) ->
      stackString += "\n"
      stackString += "    at #{frame.file}:#{frame.line}"
      stackString += " in #{frame.function}" if frame.function && frame.function != ''

    @_errors.push(message: message, stack: stackString)

  onResourceRequestedNative: (request) ->
    @lastRequestId = request.id

    if request.url == @redirectURL
      @redirectURL = null
      @requestId   = request.id

    @_networkTraffic[request.id] = {
      request:       request,
      responseParts: []
    }

  onResourceReceivedNative: (response) ->
    @_networkTraffic[response.id]?.responseParts.push(response)

    if @requestId == response.id
      if response.redirectURL
        @redirectURL = response.redirectURL
      else
        @_statusCode      = response.status
        @_responseHeaders = response.headers

  networkTraffic: ->
    @_networkTraffic

  content: ->
    @native.frameContent

  source: ->
    @_source

  errors: ->
    @_errors

  clearErrors: ->
    @_errors = []

  statusCode: ->
    @_statusCode

  responseHeaders: ->
    headers = {}
    @_responseHeaders.forEach (item) ->
      headers[item.name] = item.value
    headers

  cookies: ->
    @native.cookies

  deleteCookie: (name) ->
    @native.deleteCookie(name)

  viewportSize: ->
    @native.viewportSize

  setViewportSize: (size) ->
    @native.viewportSize = size

  scrollPosition: ->
    @native.scrollPosition

  setScrollPosition: (pos) ->
    @native.scrollPosition = pos

  clipRect: ->
    @native.clipRect

  setClipRect: (rect) ->
    @native.clipRect = rect

  setUserAgent: (userAgent) ->
    @native.settings.userAgent = userAgent

  setCustomHeaders: (headers) ->
    @native.customHeaders = headers

  pushFrame: (name) ->
    @frames.push(name)
    res = @native.switchToFrame(name)
    this.injectAgent()
    res

  popFrame: ->
    @frames.pop()

    if @frames.length == 0
      @native.switchToMainFrame()
    else
      @native.switchToFrame(@frames[@frames.length - 1])

  getPage: (name) ->
    if @sub_pages[name]
      @sub_pages[name]
    else
      page = @native.getPage(name)
      @sub_pages[name] = new Poltergeist.WebPage(page) if page

  dimensions: ->
    scroll   = this.scrollPosition()
    viewport = this.viewportSize()

    top:    scroll.top,  bottom: scroll.top  + viewport.height,
    left:   scroll.left, right:  scroll.left + viewport.width,
    viewport: viewport
    document: this.documentSize()

  # A work around for http://code.google.com/p/phantomjs/issues/detail?id=277
  validatedDimensions: ->
    dimensions = this.dimensions()
    document   = dimensions.document

    if dimensions.right > document.width
      dimensions.left  = Math.max(0, dimensions.left - (dimensions.right - document.width))
      dimensions.right = document.width

    if dimensions.bottom > document.height
      dimensions.top    = Math.max(0, dimensions.top - (dimensions.bottom - document.height))
      dimensions.bottom = document.height

    this.setScrollPosition(left: dimensions.left, top: dimensions.top)

    dimensions

  get: (id) ->
    new Poltergeist.Node(this, id)

  # Before each mouse event we make sure that the mouse is moved to where the
  # event will take place. This deals with e.g. :hover changes.
  mouseEvent: (name, x, y) ->
    this.sendEvent('mousemove', x, y)
    this.sendEvent(name, x, y)

  evaluate: (fn, args...) ->
    JSON.parse @native.evaluate("function() { return PoltergeistAgent.stringify(#{this.stringifyCall(fn, args)}) }")

  execute: (fn, args...) ->
    @native.evaluate("function() { #{this.stringifyCall(fn, args)} }")

  stringifyCall: (fn, args) ->
    if args.length == 0
      "(#{fn.toString()})()"
    else
      # The JSON.stringify happens twice because the second time we are essentially
      # escaping the string.
      "(#{fn.toString()}).apply(this, JSON.parse(#{JSON.stringify(JSON.stringify(args))}))"

  # For some reason phantomjs seems to have trouble with doing 'fat arrow' binding here,
  # hence the 'that' closure.
  bindCallback: (name) ->
    that = this
    @native[name] = ->
      if that[name + 'Native']? # For internal callbacks
        result = that[name + 'Native'].apply(that, arguments)

      if result != false && that[name]? # For externally set callbacks
        that[name].apply(that, arguments)

  # Any error raised here or inside the evaluate will get reported to
  # phantom.onError. If result is null, that means there was an error
  # inside the agent.
  runCommand: (name, args) ->
    result = this.evaluate(
      (name, args) -> __poltergeist.externalCall(name, args),
      name, args
    )

    if result.error?
      if result.error.message == 'PoltergeistAgent.ObsoleteNode'
        throw new Poltergeist.ObsoleteNode
      else
        throw new Poltergeist.JavascriptError([result.error])
    else
      result.value
