class Poltergeist
  constructor: (@port, width, height) ->
    @browser    = new Poltergeist.Browser(this, width, height)
    @connection = new Poltergeist.Connection(this, port)

    # The QtWebKit bridge doesn't seem to like Function.prototype.bind
    that = this
    phantom.onError = (message, stack) -> that.sendError(message, stack)

    env = require('system').env
    if env['SCREENSHOT_PORT']
      server = require('webserver').create()
      service = server.listen(env['SCREENSHOT_PORT'], (req, res) =>
        res.statusCode = 200

        console.log(req.url)

        if req.url == '/image'
          res.write @browser.page.native.renderBase64('PNG')
        else
          res.headers = 'Content-Type': 'text/html'

          res.write "<img><script>+#{ ->
            xhr = new XMLHttpRequest()
            xhr.open 'GET', '/image', false
            xhr.send()
            document.querySelector('img').src = "data:image/png;base64,#{xhr.responseText}"
          }()</script>"

        res.close()
      )

    @running = false

  runCommand: (command) ->
    @running = true

    try
      @browser[command.name].apply(@browser, command.args)
    catch error
      if error instanceof Poltergeist.Error
        this.sendError(error)
      else
        this.sendError(new Poltergeist.BrowserError(error.toString(), error.stack))

  sendResponse: (response) ->
    this.send(response: response)

  sendError: (error) ->
    this.send(
      error:
        name: error.name || 'Generic',
        args: error.args && error.args() || [error.toString()]
    )

  send: (data) ->
    # Prevents more than one response being sent for a single
    # command. This can happen in some scenarios where an error
    # is raised but the script can still continue.
    if @running
      @connection.send(data)
      @running = false

# This is necessary because the remote debugger will wrap the
# script in a function, causing the Poltergeist variable to
# become local.
window.Poltergeist = Poltergeist

class Poltergeist.Error

class Poltergeist.ObsoleteNode extends Poltergeist.Error
  name: "Poltergeist.ObsoleteNode"
  args: -> []
  toString: -> this.name

class Poltergeist.ClickFailed extends Poltergeist.Error
  constructor: (@selector, @position) ->
  name: "Poltergeist.ClickFailed"
  args: -> [@selector, @position]

class Poltergeist.JavascriptError extends Poltergeist.Error
  constructor: (@errors) ->
  name: "Poltergeist.JavascriptError"
  args: -> [@errors]

class Poltergeist.BrowserError extends Poltergeist.Error
  constructor: (@message, @stack) ->
  name: "Poltergeist.BrowserError"
  args: -> [@message, @stack]

# We're using phantom.libraryPath so that any stack traces
# report the full path.
phantom.injectJs("#{phantom.libraryPath}/web_page.js")
phantom.injectJs("#{phantom.libraryPath}/node.js")
phantom.injectJs("#{phantom.libraryPath}/connection.js")
phantom.injectJs("#{phantom.libraryPath}/browser.js")

new Poltergeist(phantom.args[0], phantom.args[1], phantom.args[2])
