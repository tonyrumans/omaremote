import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omaremote"
  ipcTarget: moduleName
  manageIpc: false

  property var shares: []
  property var hosts: []
  property var errors: []
  property int tab: 0
  property int selectedIndex: 0
  property string query: ""
  property bool loading: false
  property bool refreshPending: false
  property bool mutatePending: false
  property var pendingArgs: null
  property string lastAction: ""
  property string notice: ""
  property string copiedAlias: ""
  property string pendingCopyAlias: ""
  property string connectingTo: ""
  property string connectingKind: ""
  readonly property bool connecting: connectingTo !== ""

  property string shareName: ""
  property string shareType: "sshfs"
  property string shareAlias: ""
  property string shareRemote: "."
  property string shareHost: ""
  property string shareSmb: ""
  property string shareUser: ""
  property string shareMount: ""
  property string hostAlias: ""
  property string hostHostname: ""
  property string hostUser: ""
  property string hostIdentity: "~/.ssh/id_ed25519"
  property bool generateKey: false
  property string editingAlias: ""
  property string editingShare: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string omarchyPath: {
    var path = Quickshell.env("OMARCHY_PATH")
    return path && path.length ? path : "/usr/share/omarchy"
  }
  property string screensaverArt: ""
  property string defaultScreensaverArt: ""
  readonly property bool hasCustomScreensaver: screensaverArt.length > 0 && screensaverArt !== defaultScreensaverArt
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int mountedCount: Model.mountedCount(shares)
  readonly property int enabledCount: Model.enabledCount(shares)
  readonly property var filteredHosts: Model.filterHosts(hosts, query)
  readonly property var currentList: tab === 0 ? filteredHosts : shares
  readonly property var hostOptions: {
    var list = []
    var src = hosts
    for (var i = 0; i < src.length; i++) {
      var h = src[i]
      if (!h || !h.alias) continue
      var user = String(h.user || "")
      var hostname = String(h.hostname || "")
      var desc = (user && hostname) ? (user + "@" + hostname) : (hostname || user)
      list.push({ value: String(h.alias), label: String(h.alias), description: desc })
    }
    return list
  }
  readonly property bool formFocused: shareNameField.activeFocus
    || shareHostPicker.popupOpen
    || shareRemoteField.activeFocus
    || shareMountField.activeFocus
    || shareHostField.activeFocus
    || shareSmbField.activeFocus
    || shareUserField.activeFocus
    || hostAliasField.activeFocus
    || hostNameField.activeFocus
    || hostUserField.activeFocus
    || hostIdentityField.activeFocus

  function helperPath() {
    var url = String(Qt.resolvedUrl("bin/omaremote"))
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }

  component HostAction: PanelActionButton {
    required property int rowIndex
    foreground: root.dim
    hoverColor: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.icon
    size: Style.space(36)
    onHovered: function (isHovered) {
      if (isHovered)
        root.select(rowIndex)
    }
  }

  FileView {
    id: screensaverFile
    path: root.home + "/.config/omarchy/branding/screensaver.txt"
    watchChanges: true
    printErrors: false
    onLoaded: root.screensaverArt = String(text() || "")
    onLoadFailed: root.screensaverArt = ""
    onFileChanged: reload()
  }

  FileView {
    id: defaultScreensaverFile
    path: root.omarchyPath + "/logo.txt"
    printErrors: false
    onLoaded: root.defaultScreensaverArt = String(text() || "")
    onLoadFailed: root.defaultScreensaverArt = ""
  }

  function subtitle() {
    if (connectingTo !== "")
      return "Connecting to " + connectingTo + "…"
    if (loading && shares.length === 0 && hosts.length === 0)
      return "Reading…"
    if (mountedCount > 0)
      return mountedCount + (mountedCount === 1 ? " mounted" : " mounted")
    if (enabledCount > 0)
      return enabledCount + (enabledCount === 1 ? " ready" : " ready")
    if (hosts.length > 0)
      return hosts.length + (hosts.length === 1 ? " host" : " hosts")
    return "SSH + shares"
  }

  function tooltip() {
    if (mountedCount > 0)
      return "OmaRemote (" + mountedCount + " mounted)"
    if (hosts.length > 0)
      return "OmaRemote (" + hosts.length + " hosts)"
    return "OmaRemote"
  }

  function ensureSelection() {
    if (currentList.length === 0) selectedIndex = 0
    else selectedIndex = Math.max(0, Math.min(selectedIndex, currentList.length - 1))
  }

  function select(index) {
    selectedIndex = Math.max(0, Math.min(currentList.length - 1, index))
  }

  function selectedItem() {
    if (currentList.length === 0) return null
    return currentList[Math.max(0, Math.min(selectedIndex, currentList.length - 1))]
  }

  function helperCommand(args) {
    return ["python3", helperPath()].concat(args)
  }

  function beginConnecting(name, kind) {
    connectingTo = String(name || "")
    connectingKind = String(kind || "files")
    notice = ""
    errors = []
  }

  function clearConnecting() {
    var restoreSearch = connectingTo !== "" && opened
    connectingTo = ""
    connectingKind = ""
    if (restoreSearch)
      Qt.callLater(root.focusSearchAtEnd)
  }

  function runHelper(args, silent) {
    if (helperProcess.running) {
      pendingArgs = args
      return
    }
    pendingArgs = null
    if (!silent)
      loading = true
    refreshPending = false
    helperProcess.command = helperCommand(args)
    helperProcess.running = true
  }

  function refresh() {
    if (tab === 0) runHelper(["hosts", "list"])
    else runHelper(["shares", "list"])
  }

  function refreshShares() {
    runHelper(["shares", "list"])
  }

  function applyResult(raw) {
    try {
      var result = JSON.parse(String(raw || "{}"))
      if (result.ok === false) {
        notice = ""
        pendingCopyAlias = ""
        copiedAlias = ""
        lastAction = ""
        clearConnecting()
        errors = [String(result.error || "OmaRemote helper failed")]
        return
      }
      if (result.shares instanceof Array) {
        shares = result.shares
        errors = []
      }
      if (result.hosts instanceof Array) {
        hosts = result.hosts
        var hostErrors = result.errors instanceof Array ? result.errors : []
        errors = hostErrors
      }
      if (result.share && (lastAction === "add-share" || lastAction === "update-share")) {
        clearShareForm()
        Qt.callLater(refreshShares)
      }
      if (lastAction === "toggle" && result.share) {
        lastAction = ""
        errors = []
        Qt.callLater(refreshShares)
      }
      if (result.alias && (lastAction === "add-host" || lastAction === "update-host")) {
        clearHostForm()
        Qt.callLater(function() {
          runHelper(["hosts", "list"])
          root.focusSearch()
        })
      }
      if (result.removed) {
        Qt.callLater(refresh)
      }
      if ((lastAction === "files" || lastAction === "open") && (result.opened || result.uri)) {
        lastAction = ""
        notice = ""
        clearConnecting()
        close()
      }
      if (lastAction === "pubkey" && result.copied) {
        lastAction = ""
        errors = []
        pendingCopyAlias = ""
      }
    } catch (error) {
      clearConnecting()
      errors = ["Could not parse OmaRemote helper output"]
    }
    ensureSelection()
  }

  function clearShareForm() {
    editingShare = ""
    shareName = ""
    shareType = "sshfs"
    shareAlias = ""
    shareRemote = "."
    shareHost = ""
    shareSmb = ""
    shareUser = ""
    shareMount = ""
    if (shareNameField) shareNameField.text = ""
    if (shareRemoteField) shareRemoteField.text = "."
    if (shareHostField) shareHostField.text = ""
    if (shareSmbField) shareSmbField.text = ""
    if (shareUserField) shareUserField.text = ""
    if (shareMountField) shareMountField.text = ""
  }

  function clearHostForm() {
    editingAlias = ""
    hostAlias = ""
    hostHostname = ""
    hostUser = ""
    hostIdentity = "~/.ssh/id_ed25519"
    generateKey = false
    if (hostAliasField) hostAliasField.text = ""
    if (hostNameField) hostNameField.text = ""
    if (hostUserField) hostUserField.text = ""
    if (hostIdentityField) hostIdentityField.text = "~/.ssh/id_ed25519"
  }

  function editHost(host) {
    if (!host || !host.managed || !host.alias) return
    editingAlias = String(host.alias)
    hostAlias = String(host.alias)
    hostHostname = String(host.hostname || "")
    hostUser = String(host.user || "")
    hostIdentity = String(host.identityFile || "~/.ssh/id_ed25519")
    generateKey = false
    errors = []
    if (hostAliasField) hostAliasField.text = hostAlias
    if (hostNameField) hostNameField.text = hostHostname
    if (hostUserField) hostUserField.text = hostUser
    if (hostIdentityField) hostIdentityField.text = hostIdentity
  }

  function updateHost() {
    if (hostAlias === "" || hostHostname === "" || hostUser === "") {
      errors = ["Name, hostname, and user are required"]
      return
    }
    var args = [
      "hosts", "update",
      "--alias", editingAlias,
      "--hostname", hostHostname,
      "--user", hostUser,
      "--identity", hostIdentity === "" ? "~/.ssh/id_ed25519" : hostIdentity
    ]
    if (hostAlias !== editingAlias) args.push("--new-alias", hostAlias)
    if (generateKey) args.push("--generate-key")
    lastAction = "update-host"
    runHelper(args)
  }

  function saveHost() {
    if (editingAlias !== "") updateHost()
    else addHost()
  }

  function toggleShare(share, on) {
    if (!share || !share.name) return
    lastAction = "toggle"
    errors = []
    if (on)
      beginConnecting(String(share.name), "share")
    runHelper(["shares", "toggle", "--name", String(share.name), on ? "on" : "off"])
  }

  function openShare(share) {
    if (!share || !share.name) return
    lastAction = "open"
    beginConnecting(String(share.name), "share")
    runHelper(["shares", "open", "--name", String(share.name)])
  }

  function removeShare(share) {
    if (!share || !share.name) return
    lastAction = "remove-share"
    runHelper(["shares", "remove", "--name", String(share.name)])
  }

  function compactMount(path) {
    var p = String(path || "").trim()
    if (p === "") return ""
    var home = String(root.home || "")
    if (home && p.indexOf(home) === 0)
      return "~" + p.slice(home.length)
    return p
  }

  function resolvedShareName() {
    var n = String(root.shareName || "").trim()
    if (n !== "") return n
    if (root.shareType === "sshfs") return String(root.shareAlias || "").trim()
    return ""
  }

  function addShare() {
    var args
    var name = resolvedShareName()
    var mount = String(shareMount || "").trim()
    if (shareType === "sshfs") {
      if (shareAlias === "") {
        errors = ["Pick a host"]
        return
      }
      if (name === "") {
        errors = ["Share name is required"]
        return
      }
      args = ["shares", "add", "--name", name, "--type", "sshfs"]
      args.push("--ssh-alias", shareAlias, "--remote-path", shareRemote === "" ? "." : shareRemote)
    } else {
      if (name === "") {
        errors = ["Share name is required"]
        return
      }
      if (shareHost === "" || shareSmb === "") {
        errors = ["SMB host and share are required"]
        return
      }
      args = ["shares", "add", "--name", name, "--type", "smb"]
      args.push("--host", shareHost, "--share", shareSmb)
      if (shareUser !== "") args.push("--username", shareUser)
    }
    if (mount !== "") args.push("--mount-point", mount)
    lastAction = "add-share"
    runHelper(args)
  }

  function editShare(share) {
    if (!share || !share.name) return
    editingShare = String(share.name)
    shareName = String(share.name)
    shareType = String(share.type || "sshfs")
    shareAlias = String(share.sshAlias || "")
    shareRemote = String(share.remotePath || ".")
    shareHost = String(share.host || "")
    shareSmb = String(share.share || "")
    shareUser = String(share.username || "")
    shareMount = compactMount(share.mountPoint)
    errors = []
    if (shareNameField) shareNameField.text = shareName
    if (shareRemoteField) shareRemoteField.text = shareRemote
    if (shareHostField) shareHostField.text = shareHost
    if (shareSmbField) shareSmbField.text = shareSmb
    if (shareUserField) shareUserField.text = shareUser
    if (shareMountField) shareMountField.text = shareMount
    Qt.callLater(function() {
      if (shareNameField) shareNameField.forceActiveFocus()
      root.scrollItemIntoView(shareFormHeader)
    })
  }

  function updateShare() {
    var args
    var name = resolvedShareName()
    var mount = String(shareMount || "").trim()
    if (shareType === "sshfs") {
      if (shareAlias === "") {
        errors = ["Pick a host"]
        return
      }
      if (name === "") {
        errors = ["Share name is required"]
        return
      }
      args = ["shares", "update", "--name", editingShare, "--type", "sshfs"]
      if (name !== editingShare) args.push("--new-name", name)
      args.push("--ssh-alias", shareAlias, "--remote-path", shareRemote === "" ? "." : shareRemote)
    } else {
      if (name === "") {
        errors = ["Share name is required"]
        return
      }
      if (shareHost === "" || shareSmb === "") {
        errors = ["SMB host and share are required"]
        return
      }
      args = ["shares", "update", "--name", editingShare, "--type", "smb"]
      if (name !== editingShare) args.push("--new-name", name)
      args.push("--host", shareHost, "--share", shareSmb)
      if (shareUser !== "") args.push("--username", shareUser)
    }
    if (mount !== "") args.push("--mount-point", mount)
    lastAction = "update-share"
    runHelper(args)
  }

  function saveShare() {
    if (editingShare !== "") updateShare()
    else addShare()
  }

  function shareFormKey(event) {
    if (event.key === Qt.Key_Escape) {
      clearShareForm()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      saveShare()
      event.accepted = true
    }
  }

  function connectHost(host) {
    if (!host || !host.alias) return
    close()
    Quickshell.execDetached(["omarchy-launch-terminal", "ssh", "--", String(host.alias)])
  }

  function browseHost(host) {
    if (!host || !host.alias) return
    lastAction = "files"
    beginConnecting(String(host.alias), "files")
    runHelper(["hosts", "files", "--alias", String(host.alias)])
  }

  function browseSelection() {
    var item = selectedItem()
    if (!item) return
    if (tab === 0) browseHost(item)
    else openShare(item)
  }

  function copyKey(host) {
    if (!host || !host.alias) return
    lastAction = "pubkey"
    errors = []
    var alias = String(host.alias)
    pendingCopyAlias = alias
    if (copiedAlias === alias) {
      copiedAlias = ""
      Qt.callLater(function() { root.copiedAlias = alias })
    } else {
      copiedAlias = alias
    }
    runHelper(["hosts", "pubkey", "--alias", alias], true)
  }

  function copySelectionKey() {
    if (tab !== 0) return
    var item = selectedItem()
    if (item) copyKey(item)
  }

  function removeHost(host) {
    if (!host || !host.alias || !host.managed) return
    lastAction = "remove-host"
    runHelper(["hosts", "remove", "--alias", String(host.alias)])
  }

  function addHost() {
    if (hostAlias === "" || hostHostname === "" || hostUser === "") {
      errors = ["Name, hostname, and user are required"]
      return
    }
    var args = [
      "hosts", "add",
      "--alias", hostAlias,
      "--hostname", hostHostname,
      "--user", hostUser,
      "--identity", hostIdentity === "" ? "~/.ssh/id_ed25519" : hostIdentity
    ]
    if (generateKey) args.push("--generate-key")
    lastAction = "add-host"
    runHelper(args)
  }

  function activateSelection() {
    var item = selectedItem()
    if (!item) return
    if (tab === 0) connectHost(item)
    else openShare(item)
  }

  function editSelection() {
    var item = selectedItem()
    if (!item) return
    if (tab === 1) {
      editShare(item)
      return
    }
    if (tab !== 0) return
    if (!item.managed) {
      errors = ["Only OmaRemote-managed hosts can be edited"]
      return
    }
    editHost(item)
    Qt.callLater(function() {
      if (hostNameField) hostNameField.forceActiveFocus()
      root.scrollItemIntoView(hostFormHeader)
    })
  }

  function focusSearch() {
    if (tab !== 0 || !searchField) return
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function focusSearchAtEnd() {
    if (!opened || tab !== 0 || !searchField) return
    searchField.forceActiveFocus()
    Qt.callLater(function() {
      if (!searchField || !root.opened) return
      searchField.cursorPosition = searchField.text.length
    })
  }

  function hostFormKey(event) {
    if (event.key === Qt.Key_Escape) {
      clearHostForm()
      Qt.callLater(root.focusSearch)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      saveHost()
      event.accepted = true
    }
  }

  function scrollItemIntoView(item) {
    if (!item || !panelFlick) return
    Qt.callLater(function() {
      if (!item) return
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var margin = Style.space(6)
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function moveSelection(delta) {
    if (currentList.length === 0) return
    selectedIndex = Math.max(0, Math.min(currentList.length - 1, selectedIndex + delta))
    if (tab === 0) scrollItemIntoView(hostListColumn.children[selectedIndex])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onTabChanged: {
    selectedIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    refresh()
    if (tab === 0) Qt.callLater(root.focusSearch)
    else if (tab === 1) Qt.callLater(function() { if (sharesColumn) sharesColumn.forceActiveFocus() })
  }
  onFilteredHostsChanged: {
    selectedIndex = 0
    if (tab === 0 && panelFlick) panelFlick.contentY = 0
  }
  onOpenedChanged: if (opened) {
    query = ""
    selectedIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    if (tab !== 0) tab = 0
    else refresh()
    Qt.callLater(root.focusSearch)
  } else {
    query = ""
    clearHostForm()
    clearShareForm()
    if (!helperProcess.running) clearConnecting()
  }

  Component.onCompleted: refresh()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function count(): int { return root.mountedCount }
  }

  Process {
    id: helperProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyResult(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.errors = [message]
      }
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0 && root.errors.length === 0)
        root.errors = ["OmaRemote helper failed"]
      var next = root.pendingArgs
      root.pendingArgs = null
      if (next) {
        Qt.callLater(function() { root.runHelper(next) })
        return
      }
      root.clearConnecting()
      if (root.refreshPending) Qt.callLater(root.refresh)
    }
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰉌"
    active: root.opened || root.connecting
    tooltipText: root.connecting ? ("Connecting to " + root.connectingTo + "…") : root.tooltip()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else {
        if (!root.opened) {
          root.query = ""
          root.selectedIndex = 0
          root.tab = 0
        }
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.tab === 0 ? searchField : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.formFocused || (root.tab === 0 && searchField.activeFocus)
      onMoveRequested: function(dx, dy) {
        if (root.connecting || dy === 0) return
        root.moveSelection(dy)
      }
      onActivateRequested: { if (!root.connecting) root.activateSelection() }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { if (!root.connecting) root.switchPanel(direction) }
      onTextKey: function(text) {
        if (root.connecting || root.tab !== 0) return
        root.query += text
        root.focusSearch()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: panelFlick.width
          spacing: Style.space(10)

          RowLayout {
            width: parent.width
            spacing: Style.space(10)

            Text {
              text: "󰉌"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              Text {
                text: "OmaRemote"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.weight: Font.DemiBold
              }
              Text {
                text: root.subtitle()
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Text {
              id: headerBusy
              visible: root.loading || root.connecting
              text: "󰦖"
              textFormat: Text.PlainText
              color: root.connecting ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body

              RotationAnimator on rotation {
                running: headerBusy.visible
                from: 0
                to: 360
                duration: 800
                loops: Animation.Infinite
              }

              onVisibleChanged: if (!visible) rotation = 0
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(18)

            Text {
              text: "Hosts"
              textFormat: Text.PlainText
              color: root.tab === 0 ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: root.tab === 0 ? Font.DemiBold : Font.Normal
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.tab = 0
              }
            }

            Text {
              text: "Shares"
              textFormat: Text.PlainText
              color: root.tab === 1 ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: root.tab === 1 ? Font.DemiBold : Font.Normal
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.tab = 1
              }
            }
          }

          TextField {
            id: searchField
            visible: root.tab === 0
            width: parent.width
            foreground: root.foreground
            placeholderText: "Search hosts…"
            text: root.query
            onTextChanged: root.query = text
            Keys.onPressed: function(event) {
              if (root.connecting) {
                if (event.key === Qt.Key_Escape) root.close()
                event.accepted = true
                return
              }
              if (event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (event.modifiers & Qt.ControlModifier) root.browseSelection()
                else if (event.modifiers & Qt.ShiftModifier) root.editSelection()
                else root.activateSelection()
                event.accepted = true
              } else if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
                root.copySelectionKey()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                if (text !== "") text = ""
                else root.close()
                event.accepted = true
              }
            }
          }

          Text {
            visible: root.errors.length > 0
            width: parent.width
            text: root.errors.length > 0 ? String(root.errors[0]) : ""
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            foreground: root.foreground
          }

          // ---------------- Shares ----------------
          Column {
            id: sharesColumn
            width: parent.width
            spacing: Style.space(8)
            visible: root.tab === 1
            focus: root.opened && root.tab === 1 && !root.formFocused
            Keys.onPressed: function(event) {
              if (root.connecting) {
                if (event.key === Qt.Key_Escape) root.close()
                event.accepted = true
                return
              }
              if (event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (event.modifiers & Qt.ShiftModifier) root.editSelection()
                else if (event.modifiers & Qt.ControlModifier) root.browseSelection()
                else root.activateSelection()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
              }
            }

            Text {
              visible: !root.loading && root.shares.length === 0
              width: parent.width
              topPadding: Style.space(8)
              bottomPadding: Style.space(8)
              text: "No shares yet. Add an sshfs or SMB share."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.shares

                CursorSurface {
                  id: shareRow
                  required property var modelData
                  required property int index
                  readonly property bool live: !!modelData.mounted
                  width: parent.width
                  implicitHeight: Style.space(56)
                  clip: true
                  hasCursor: root.tab === 1 && index === root.selectedIndex
                  current: live
                  foreground: root.foreground
                  fill: Style.selectedFillFor(root.foreground, Color.accent)
                  property real glowPulse: 0.22

                  SequentialAnimation {
                    running: shareRow.live
                    loops: Animation.Infinite
                    NumberAnimation {
                      target: shareRow
                      property: "glowPulse"
                      from: 0.16
                      to: 0.40
                      duration: 1600
                      easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                      target: shareRow
                      property: "glowPulse"
                      from: 0.40
                      to: 0.16
                      duration: 1600
                      easing.type: Easing.InOutSine
                    }
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)

                    Item {
                      Layout.preferredWidth: Style.space(10)
                      Layout.preferredHeight: Style.space(16)

                      Rectangle {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 6
                        color: Color.accent
                        opacity: shareRow.live ? shareRow.glowPulse : 0
                      }

                      Rectangle {
                        anchors.centerIn: parent
                        width: 6
                        height: 6
                        radius: 3
                        color: Color.accent
                        opacity: shareRow.live ? 1 : 0
                      }
                    }

                    Text {
                      Layout.preferredWidth: Style.space(18)
                      text: modelData.type === "smb" ? "󰖲" : "󰣀"
                      textFormat: Text.PlainText
                      color: shareRow.live ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      horizontalAlignment: Text.AlignHCenter
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 0

                      Text {
                        Layout.fillWidth: true
                        text: String(modelData.name || "")
                        textFormat: Text.PlainText
                        color: shareRow.live ? Style.selectedStateColor(root.foreground, Color.accent) : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                      }

                      Text {
                        Layout.fillWidth: true
                        text: Model.shareSource(modelData) + " · " + Model.stateLabel(modelData)
                        textFormat: Text.PlainText
                        color: modelData.state === "error" ? root.urgent : (shareRow.live ? Color.accent : root.dim)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        opacity: modelData.state === "error" ? 1 : (shareRow.live ? 0.85 : 1)
                        elide: Text.ElideRight
                      }
                    }

                    HostAction {
                      rowIndex: shareRow.index
                      iconText: shareRow.modelData.enabled ? "󰐥" : "󰐦"
                      tooltipText: shareRow.modelData.enabled ? "Disable share" : "Enable share"
                      foreground: shareRow.live ? Color.accent : (shareRow.modelData.enabled ? root.foreground : root.dim)
                      onClicked: root.toggleShare(shareRow.modelData, !shareRow.modelData.enabled)
                    }

                    HostAction {
                      rowIndex: shareRow.index
                      iconText: "󰏫"
                      tooltipText: "Edit share"
                      onClicked: root.editShare(shareRow.modelData)
                    }

                    HostAction {
                      rowIndex: shareRow.index
                      iconText: "󰅖"
                      tooltipText: "Remove share"
                      hoverColor: root.urgent
                      onClicked: root.removeShare(shareRow.modelData)
                    }
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: parent.height - Style.space(8)
                    radius: 5
                    color: Color.accent
                    opacity: shareRow.live ? shareRow.glowPulse : 0
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: parent.height - Style.space(10)
                    radius: 1
                    color: Color.accent
                    opacity: shareRow.live ? 1 : (shareRow.hasCursor ? 1 : 0)
                    Behavior on opacity {
                      NumberAnimation { duration: 80 }
                    }
                  }

                  HoverHandler {
                    onHoveredChanged: if (hovered)
                      root.select(shareRow.index)
                  }

                  MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: Style.space(140)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openShare(shareRow.modelData)
                  }
                }
              }
            }

            PanelSeparator {
              foreground: root.foreground
            }

            RowLayout {
              id: shareFormHeader
              width: parent.width
              Text {
                Layout.fillWidth: true
                text: root.editingShare === "" ? "Add share" : "Edit " + root.editingShare
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              Text {
                visible: root.editingShare !== ""
                text: "Cancel"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.clearShareForm()
                }
              }
            }

            Row {
              spacing: Style.space(16)
              Text {
                text: "sshfs"
                textFormat: Text.PlainText
                color: root.shareType === "sshfs" ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: root.shareType === "sshfs" ? Font.DemiBold : Font.Normal
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.shareType = "sshfs"
                }
              }
              Text {
                text: "smb"
                textFormat: Text.PlainText
                color: root.shareType === "smb" ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: root.shareType === "smb" ? Font.DemiBold : Font.Normal
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.shareType = "smb"
                }
              }
            }

            TextField {
              id: shareNameField
              width: parent.width
              Keys.onPressed: root.shareFormKey(event)
              foreground: root.foreground
              placeholderText: root.shareType === "sshfs" ? "Name (default: host)" : "Name"
              text: root.shareName
              onTextChanged: root.shareName = text
            }

            Text {
              visible: root.shareType === "sshfs" && root.hosts.length === 0
              width: parent.width
              text: "Add a host first, then pick it here."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            SearchableDropdown {
              id: shareHostPicker
              visible: root.shareType === "sshfs" && root.hosts.length > 0
              width: parent.width
              showLabel: false
              placeholderText: "Host"
              emptyText: "No matching hosts"
              fontFamily: root.fontFamily
              foreground: root.foreground
              options: root.hostOptions
              value: root.shareAlias
              onChanged: function(v) {
                var prev = root.shareAlias
                root.shareAlias = v
                if (root.editingShare === "" && (root.shareName === "" || root.shareName === prev)) {
                  root.shareName = v
                  if (shareNameField) shareNameField.text = v
                }
              }
            }

            TextField {
              id: shareRemoteField
              width: parent.width
              Keys.onPressed: root.shareFormKey(event)
              visible: root.shareType === "sshfs"
              foreground: root.foreground
              placeholderText: "Remote path (default .)"
              text: root.shareRemote
              onTextChanged: root.shareRemote = text
            }

            TextField {
              id: shareHostField
              width: parent.width
              Keys.onPressed: root.shareFormKey(event)
              visible: root.shareType === "smb"
              foreground: root.foreground
              placeholderText: "Host"
              text: root.shareHost
              onTextChanged: root.shareHost = text
            }

            TextField {
              id: shareSmbField
              width: parent.width
              Keys.onPressed: root.shareFormKey(event)
              visible: root.shareType === "smb"
              foreground: root.foreground
              placeholderText: "Share"
              text: root.shareSmb
              onTextChanged: root.shareSmb = text
            }

            TextField {
              id: shareUserField
              width: parent.width
              Keys.onPressed: root.shareFormKey(event)
              visible: root.shareType === "smb"
              foreground: root.foreground
              placeholderText: "Username (optional)"
              text: root.shareUser
              onTextChanged: root.shareUser = text
            }

            TextField {
              id: shareMountField
              width: parent.width
              Keys.onPressed: root.shareFormKey(event)
              foreground: root.foreground
              placeholderText: "Mount point (default ~/mnt/<name>)"
              text: root.shareMount
              onTextChanged: root.shareMount = text
            }

            CursorSurface {
              width: parent.width
              implicitHeight: Style.space(40)
              foreground: root.foreground
              Text {
                anchors.centerIn: parent
                text: root.editingShare === "" ? "Add" : "Save"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveShare()
              }
            }
          }

          // ---------------- Hosts ----------------
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.tab === 0

            Text {
              visible: !root.loading && root.filteredHosts.length === 0
              width: parent.width
              topPadding: Style.space(8)
              bottomPadding: Style.space(8)
              text: root.hosts.length === 0
                ? "No SSH hosts found"
                : "No matching SSH hosts"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: hostListColumn
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.filteredHosts

                CursorSurface {
                  id: hostRow
                  required property var modelData
                  required property int index
                  width: parent.width
                  implicitHeight: Style.space(56)
                  clip: true
                  hasCursor: root.tab === 0 && index === root.selectedIndex && copiedMsgOpacity < 0.2
                  foreground: root.foreground
                  fill: Style.selectedFillFor(root.foreground, Color.accent)
                  property real sweepPos: 1
                  property real contentOpacity: 1
                  property real copiedMsgOpacity: 0
                  property real overlayOpacity: 1
                  readonly property bool celebrating: root.copiedAlias !== "" && String(modelData.alias || "") === root.copiedAlias

                  onCelebratingChanged: {
                    if (celebrating)
                      copyAnim.restart()
                    else {
                      copyAnim.stop()
                      sweepPos = 1
                      contentOpacity = 1
                      copiedMsgOpacity = 0
                      overlayOpacity = 1
                    }
                  }

                  SequentialAnimation {
                    id: copyAnim
                    ScriptAction {
                      script: {
                        hostRow.sweepPos = 1
                        hostRow.contentOpacity = 1
                        hostRow.copiedMsgOpacity = 0
                        hostRow.overlayOpacity = 1
                      }
                    }
                    NumberAnimation {
                      target: hostRow
                      property: "sweepPos"
                      from: 1
                      to: 0
                      duration: 520
                      easing.type: Easing.InOutCubic
                    }
                    ScriptAction {
                      script: hostRow.contentOpacity = 0
                    }
                    NumberAnimation {
                      target: hostRow
                      property: "copiedMsgOpacity"
                      to: 1
                      duration: 160
                      easing.type: Easing.OutCubic
                    }
                    PauseAnimation { duration: 1250 }
                    ParallelAnimation {
                      NumberAnimation {
                        target: hostRow
                        property: "copiedMsgOpacity"
                        to: 0
                        duration: 160
                      }
                      NumberAnimation {
                        target: hostRow
                        property: "overlayOpacity"
                        to: 0
                        duration: 220
                        easing.type: Easing.OutCubic
                      }
                      NumberAnimation {
                        target: hostRow
                        property: "contentOpacity"
                        to: 1
                        duration: 220
                        easing.type: Easing.OutCubic
                      }
                    }
                    ScriptAction {
                      script: {
                        hostRow.sweepPos = 1
                        hostRow.overlayOpacity = 1
                      }
                    }
                    ScriptAction {
                      script: {
                        if (root.copiedAlias === String(hostRow.modelData.alias || ""))
                          root.copiedAlias = ""
                      }
                    }
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: parent.height - Style.space(10)
                    radius: 1
                    color: Color.accent
                    opacity: hostRow.hasCursor ? 1 : 0
                    Behavior on opacity {
                      NumberAnimation { duration: 80 }
                    }
                  }

                  HoverHandler {
                    onHoveredChanged: if (hovered)
                      root.select(hostRow.index)
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(6)
                    opacity: hostRow.contentOpacity
                    enabled: hostRow.contentOpacity > 0.8
                    visible: hostRow.contentOpacity > 0

                    Item {
                      Layout.fillWidth: true
                      Layout.fillHeight: true

                      RowLayout {
                        anchors.fill: parent
                        spacing: Style.space(8)

                        Text {
                          Layout.preferredWidth: Style.space(18)
                          text: modelData.managed ? "󰢻" : "󰒍"
                          textFormat: Text.PlainText
                          color: hostRow.hasCursor ? root.foreground : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          horizontalAlignment: Text.AlignHCenter
                        }

                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 0
                          Text {
                            Layout.fillWidth: true
                            text: String(modelData.alias || "")
                            textFormat: Text.PlainText
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                          }
                          Text {
                            Layout.fillWidth: true
                            text: String(modelData.details || modelData.alias || "")
                            textFormat: Text.PlainText
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                          }
                        }

                        Text {
                          text: "󰁔"
                          textFormat: Text.PlainText
                          color: hostRow.hasCursor ? root.foreground : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.connectHost(hostRow.modelData)
                      }
                    }

                    HostAction {
                      rowIndex: hostRow.index
                      iconText: "󰉋"
                      tooltipText: "Open files"
                      onClicked: root.browseHost(hostRow.modelData)
                    }

                    HostAction {
                      rowIndex: hostRow.index
                      iconText: "󰌆"
                      tooltipText: "Copy public key"
                      onClicked: root.copyKey(hostRow.modelData)
                    }

                    HostAction {
                      rowIndex: hostRow.index
                      visible: !!modelData.managed
                      iconText: "󰏫"
                      tooltipText: "Edit host"
                      onClicked: root.editHost(hostRow.modelData)
                    }

                    HostAction {
                      rowIndex: hostRow.index
                      visible: !!modelData.managed
                      iconText: "󰅖"
                      tooltipText: "Remove host"
                      hoverColor: root.urgent
                      onClicked: root.removeHost(hostRow.modelData)
                    }
                  }

                  Item {
                    anchors.fill: parent
                    z: 8
                    visible: copyAnim.running
                    clip: true
                    opacity: hostRow.overlayOpacity

                    Rectangle {
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      anchors.right: parent.right
                      width: (1 - hostRow.sweepPos) * parent.width
                      color: Color.background
                    }

                    Rectangle {
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: Style.space(88)
                      x: hostRow.sweepPos * parent.width - width
                      gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.28; color: Color.accent }
                        GradientStop { position: 0.72; color: Color.accent }
                        GradientStop { position: 1.0; color: Color.background }
                      }
                    }
                  }

                  Row {
                    anchors.centerIn: parent
                    z: 9
                    spacing: Style.space(10)
                    opacity: hostRow.copiedMsgOpacity
                    visible: hostRow.copiedMsgOpacity > 0

                    Text {
                      text: "󰌆"
                      textFormat: Text.PlainText
                      color: Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      text: "SSH Key Copied"
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.weight: Font.DemiBold
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }
            }

            PanelSeparator {
              foreground: root.foreground
            }

            RowLayout {
              id: hostFormHeader
              width: parent.width
              Text {
                Layout.fillWidth: true
                text: root.editingAlias === "" ? "Add host" : "Edit " + root.editingAlias
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              Text {
                visible: root.editingAlias !== ""
                text: "Cancel"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.clearHostForm()
                }
              }
            }

            TextField {
              id: hostAliasField
              width: parent.width
              Keys.onPressed: root.hostFormKey(event)
              foreground: root.foreground
              placeholderText: "Name"
              text: root.hostAlias
              onTextChanged: root.hostAlias = text
            }

            TextField {
              id: hostNameField
              width: parent.width
              Keys.onPressed: root.hostFormKey(event)
              foreground: root.foreground
              placeholderText: "Hostname"
              text: root.hostHostname
              onTextChanged: root.hostHostname = text
            }

            TextField {
              id: hostUserField
              width: parent.width
              Keys.onPressed: root.hostFormKey(event)
              foreground: root.foreground
              placeholderText: "User"
              text: root.hostUser
              onTextChanged: root.hostUser = text
            }

            TextField {
              id: hostIdentityField
              width: parent.width
              Keys.onPressed: root.hostFormKey(event)
              visible: !root.generateKey
              foreground: root.foreground
              placeholderText: "Identity file"
              text: root.hostIdentity
              onTextChanged: root.hostIdentity = text
            }

            CursorSurface {
              width: parent.width
              implicitHeight: Style.space(36)
              foreground: root.foreground
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                text: root.generateKey ? "󰄲  Generate new key" : "󰄱  Generate new key"
                textFormat: Text.PlainText
                color: root.generateKey ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.generateKey = !root.generateKey
              }
            }

            CursorSurface {
              width: parent.width
              implicitHeight: Style.space(40)
              foreground: root.foreground
              Text {
                anchors.centerIn: parent
                text: root.editingAlias === "" ? "Add" : "Save"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveHost()
              }
            }
          }

          Text {
            width: parent.width
            text: root.connecting
              ? "Connecting…   Esc close"
              : root.tab === 0
                ? "↑↓ select   Enter connect   Shift+Enter edit   Esc close"
                : "Click name to open   Shift+Enter edit   power toggles   Esc close"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }

      Item {
        id: connectingOverlay
        anchors.fill: parent
        visible: root.connecting
        z: 20
        focus: visible
        activeFocusOnTab: false
        onVisibleChanged: {
          if (visible) forceActiveFocus()
          else Qt.callLater(root.focusSearchAtEnd)
        }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          }
        }

        Rectangle {
          anchors.fill: parent
          color: Color.background
          opacity: 0.88
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(14)
          width: parent.width - Style.space(48)

          Item {
            id: screensaverStage
            visible: root.hasCustomScreensaver
            width: parent.width
            height: Math.max(Style.space(96), Math.round(connectingOverlay.height * 0.4))
            clip: true

            Item {
              id: markDrift
              width: parent.width
              height: parent.height
              transformOrigin: Item.Center

              SequentialAnimation on y {
                running: root.connecting && screensaverStage.visible
                loops: Animation.Infinite
                NumberAnimation { from: 10; to: -10; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { from: -10; to: 10; duration: 1100; easing.type: Easing.InOutSine }
              }

              SequentialAnimation on scale {
                running: root.connecting && screensaverStage.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0.94; to: 1.08; duration: 1600; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.08; to: 0.94; duration: 1600; easing.type: Easing.InOutSine }
              }

              SequentialAnimation on x {
                running: root.connecting && screensaverStage.visible
                loops: Animation.Infinite
                NumberAnimation { from: -5; to: 5; duration: 1700; easing.type: Easing.InOutSine }
                NumberAnimation { from: 5; to: -5; duration: 1700; easing.type: Easing.InOutSine }
              }

              Text {
                id: screensaverGhost
                anchors.fill: parent
                anchors.leftMargin: 3
                anchors.topMargin: 4
                text: root.screensaverArt
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.22
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                fontSizeMode: Text.Fit
                minimumPixelSize: 6
                wrapMode: Text.NoWrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }

              Text {
                id: screensaverMark
                anchors.fill: parent
                text: root.screensaverArt
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                fontSizeMode: Text.Fit
                minimumPixelSize: 6
                wrapMode: Text.NoWrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                SequentialAnimation on opacity {
                  running: root.connecting && screensaverStage.visible
                  loops: Animation.Infinite
                  NumberAnimation { from: 0.55; to: 1.0; duration: 520; easing.type: Easing.InOutSine }
                  NumberAnimation { from: 1.0; to: 0.55; duration: 520; easing.type: Easing.InOutSine }
                }
              }
            }

            Rectangle {
              id: markScan
              width: parent.width
              height: Style.space(28)
              gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.34) }
                GradientStop { position: 1.0; color: "transparent" }
              }

              SequentialAnimation on y {
                running: root.connecting && screensaverStage.visible
                loops: Animation.Infinite
                NumberAnimation {
                  from: -Style.space(32)
                  to: screensaverStage.height + Style.space(8)
                  duration: 780
                  easing.type: Easing.InOutCubic
                }
                PauseAnimation { duration: 120 }
              }
            }
          }

          Text {
            id: connectGlyph
            anchors.horizontalCenter: parent.horizontalCenter
            text: "󰦖"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.hasCustomScreensaver ? Style.font.title : Style.font.display

            RotationAnimator on rotation {
              running: root.connecting
              from: 0
              to: 360
              duration: 900
              loops: Animation.Infinite
            }

            SequentialAnimation on opacity {
              running: root.connecting
              loops: Animation.Infinite
              NumberAnimation { from: 1.0; to: 0.4; duration: 700; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.4; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
            }
          }

          Text {
            width: parent.width
            text: root.connectingTo === "" ? "Connecting…" : "Connecting to " + root.connectingTo
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: root.connectingKind === "share" ? "Opening share…" : "Opening files…"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
          }

          Item {
            id: scanTrack
            width: parent.width
            height: Style.space(3)
            clip: true

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: root.foreground
              opacity: 0.12
            }

            Rectangle {
              id: scanBar
              width: Math.max(Style.space(48), scanTrack.width * 0.3)
              height: parent.height
              radius: height / 2
              color: root.foreground

              SequentialAnimation on x {
                running: root.connecting
                loops: Animation.Infinite
                NumberAnimation {
                  from: -Style.space(80)
                  to: Style.space(400)
                  duration: 1100
                  easing.type: Easing.InOutCubic
                }
              }
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {}
        }
      }

    }
  }
}
