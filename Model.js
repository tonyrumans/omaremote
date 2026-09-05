.pragma library

function shareSource(share) {
  if (!share) return ""
  if (share.source) return String(share.source)
  if (share.type === "sshfs")
    return "sshfs " + String(share.sshAlias || "") + ":" + String(share.remotePath || ".")
  if (share.type === "smb") {
    var user = String(share.username || "")
    var host = String(share.host || "")
    var name = String(share.share || "")
    if (user) return "smb " + user + "@" + host + "/" + name
    return "smb " + host + "/" + name
  }
  return String(share.type || "")
}

function mountedCount(shares) {
  var list = shares instanceof Array ? shares : []
  var count = 0
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].mounted) count++
  }
  return count
}

function enabledCount(shares) {
  var list = shares instanceof Array ? shares : []
  var count = 0
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].enabled) count++
  }
  return count
}

function stateLabel(share) {
  if (!share) return ""
  var state = String(share.state || "")
  if (state === "mounted") return "mounted"
  if (state === "automount") return "ready"
  if (state === "error") return share.error ? String(share.error) : "error"
  return "off"
}

function identityPub(path) {
  var value = String(path || "")
  if (value === "") return ""
  if (value.slice(-4) === ".pub") return value
  return value + ".pub"
}

function fuzzyScore(text, query) {
  var haystack = String(text || "").toLowerCase()
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return 0

  var direct = haystack.indexOf(needle)
  if (direct !== -1) return 1000 - direct

  var score = 0
  var position = -1
  var previous = -2
  for (var i = 0; i < needle.length; i++) {
    position = haystack.indexOf(needle.charAt(i), position + 1)
    if (position === -1) return -1
    score += position === previous + 1 ? 12 : 3
    score -= Math.min(position, 30) * 0.05
    previous = position
  }
  return score
}

function hostSearchText(host) {
  if (!host) return ""
  if (host.searchText) return String(host.searchText)
  return [host.alias, host.hostname, host.user, host.details, host.identityFile]
    .map(function(part) { return String(part || "") })
    .join(" ")
}

function filterHosts(hosts, query) {
  var source = hosts instanceof Array ? hosts : []
  var terms = String(query || "").trim().toLowerCase().split(/\s+/).filter(function(term) {
    return term !== ""
  })
  if (terms.length === 0) return source

  var matches = []
  for (var i = 0; i < source.length; i++) {
    var host = source[i]
    var text = hostSearchText(host)
    var score = 0
    var matched = true
    for (var j = 0; j < terms.length; j++) {
      var termScore = fuzzyScore(text, terms[j])
      if (termScore < 0) {
        matched = false
        break
      }
      score += termScore
    }
    if (matched) matches.push({ host: host, score: score, index: i })
  }

  matches.sort(function(a, b) {
    if (a.score !== b.score) return b.score - a.score
    return a.index - b.index
  })
  return matches.map(function(match) { return match.host })
}
