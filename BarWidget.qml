import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy-nbl-scores"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string dataPath: home + "/.local/state/omarchy/nbl/data.json"
  readonly property string scriptPath: Qt.resolvedUrl("fetch_nbl.py").toString().replace(/^file:\/\//, "")

  property var nblData: ({})
  property string activeTab: "scores" // "scores", "schedule", "standings"
  property bool popupOpen: false
  readonly property bool opened: popupOpen

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color bg: root.bar ? root.bar.background : Color.background
  readonly property string fFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color dimFg: Qt.darker(fg, 1.45)
  readonly property color cardBg: Qt.rgba(fg.r, fg.g, fg.b, 0.06)
  readonly property color cardBorder: Qt.rgba(fg.r, fg.g, fg.b, 0.12)

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }

  function refresh() {
    if (fetchProcess.running) return
    fetchProcess.command = ["python3", root.scriptPath, "--json"]
    fetchProcess.running = true
  }

  FileView {
    id: dataFile
    path: root.dataPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.reloadJson()
    onFileChanged: reload()
  }

  function reloadJson() {
    try {
      var content = typeof dataFile.text === "function" ? dataFile.text() : dataFile.text
      if (content && String(content).trim() !== "") {
        root.nblData = JSON.parse(content)
      }
    } catch (e) {
      console.warn("NBL Plugin JSON parse error:", e)
    }
  }

  Component.onCompleted: {
    root.reloadJson()
    root.refresh()
  }

  // Timer: 30s when a match is live, 300s (5m) when idle
  Timer {
    id: pollTimer
    interval: (root.nblData && root.nblData.has_live) ? 30000 : 300000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: fetchProcess
    command: ["python3", root.scriptPath, "--json"]
    running: false

    stdout: StdioCollector {
      id: fetchStdout
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: fetchStderr
      waitForEnd: true
    }

    onExited: function(exitCode) {
      if (exitCode === 0) {
        var raw = String(fetchStdout.text || "").trim()
        if (raw) {
          try {
            root.nblData = JSON.parse(raw)
          } catch (e) {
            console.warn("NBL Plugin JSON parse error:", e)
          }
        }
        dataFile.reload()
      } else {
        console.warn("fetch_nbl.py failed with code:", exitCode, fetchStderr.text)
      }
    }
  }

  visible: true
  implicitWidth: barButton.implicitWidth
  implicitHeight: barSize

  WidgetButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: root.nblData && root.nblData.bar_summary ? root.nblData.bar_summary : "🏀 NBL"
    active: root.nblData && root.nblData.has_live === true
    useActiveColor: true
    horizontalMargin: 8
    tooltipText: "NBL Match Center — Left-click: Open Panel | Right-click: Refresh | Middle-click: ESPN Website"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        root.refresh()
      } else if (buttonCode === Qt.MiddleButton) {
        Quickshell.execDetached(["xdg-open", "https://www.espn.com/nbl/scoreboard"])
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(460))
    contentHeight: popup.fittedContentHeight(mainColumn.implicitHeight, Style.space(620))

    Column {
      id: mainColumn
      width: parent.width
      spacing: Style.space(12)

      // 1. Header
      RowLayout {
        width: parent.width

        Text {
          text: "🏀 NBL MATCH CENTER"
          color: root.fg
          font.family: root.fFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        Text {
          text: root.nblData && root.nblData.last_updated ? ("Updated " + root.nblData.last_updated) : ""
          color: root.dimFg
          font.family: root.fFamily
          font.pixelSize: Style.font.caption
          Layout.alignment: Qt.AlignVCenter
        }

        Button {
          iconText: "󰑐"
          tooltipText: fetchProcess.running ? "Updating scores..." : "Refresh scores from ESPN"
          foreground: fetchProcess.running ? Color.accent : root.fg
          iconSpinning: fetchProcess.running
          enabled: !fetchProcess.running
          Layout.alignment: Qt.AlignVCenter
          onClicked: root.refresh()
        }

        Button {
          iconText: "󰌹"
          tooltipText: "Open ESPN NBL Scoreboard in browser"
          foreground: root.fg
          Layout.alignment: Qt.AlignVCenter
          onClicked: Quickshell.execDetached(["xdg-open", "https://www.espn.com/nbl/scoreboard"])
        }
      }

      PanelSeparator {
        foreground: root.fg
      }

      // 2. Navigation Tabs
      Row {
        width: parent.width
        spacing: Style.space(8)

        Button {
          text: "Scores"
          iconText: "󰡂"
          foreground: root.fg
          selected: root.activeTab === "scores"
          bordered: true
          onClicked: root.activeTab = "scores"
        }

        Button {
          text: "Schedule"
          iconText: "󰃭"
          foreground: root.fg
          selected: root.activeTab === "schedule"
          bordered: true
          onClicked: root.activeTab = "schedule"
        }

        Button {
          text: "Standings"
          iconText: "󰑋"
          foreground: root.fg
          selected: root.activeTab === "standings"
          bordered: true
          onClicked: root.activeTab = "standings"
        }
      }

      // 3. Tab Views Container
      Item {
        id: viewViewport
        width: parent.width
        height: Style.space(460)
        clip: true

        Flickable {
          id: contentFlick
          anchors.fill: parent
          contentWidth: width
          contentHeight: dynamicContent.implicitHeight
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds

          WheelHandler {
            target: contentFlick
            onWheel: function(event) {
              var step = event.angleDelta.y
              contentFlick.contentY = Math.max(0, Math.min(contentFlick.contentHeight - contentFlick.height, contentFlick.contentY - step))
            }
          }

          Column {
            id: dynamicContent
            width: parent.width
            spacing: Style.space(10)

            // ==================== TAB 1: SCORES ====================
            Column {
              id: scoresTab
              visible: root.activeTab === "scores"
              width: parent.width
              spacing: Style.space(10)

              // Live Games Section
              Column {
                visible: !!(root.nblData && root.nblData.live_games && root.nblData.live_games.length > 0)
                width: parent.width
                spacing: Style.space(8)

                PanelSectionHeader {
                  text: "LIVE MATCHES"
                  foreground: Color.urgent
                  fontFamily: root.fFamily
                }

                Repeater {
                  model: root.nblData ? (root.nblData.live_games || []) : []
                  delegate: Rectangle {
                    id: liveCard
                    required property var modelData
                    width: parent.width
                    implicitHeight: liveCardCol.implicitHeight + Style.space(16)
                    radius: 8
                    color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.1)
                    border.color: Color.urgent
                    border.width: 1

                    Column {
                      id: liveCardCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.space(8)
                      spacing: Style.space(6)

                      RowLayout {
                        width: parent.width
                        Rectangle {
                          width: 8; height: 8; radius: 4; color: Color.urgent
                          SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.2; duration: 600 }
                            NumberAnimation { from: 0.2; to: 1.0; duration: 600 }
                          }
                        }
                        Text {
                          text: "LIVE • " + (liveCard.modelData.status_detail || "")
                          color: Color.urgent
                          font.bold: true
                          font.pixelSize: Style.font.caption
                          font.family: root.fFamily
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                          text: liveCard.modelData.venue || ""
                          color: root.dimFg
                          font.pixelSize: Style.font.caption
                          font.family: root.fFamily
                          elide: Text.ElideRight
                        }
                      }

                      // Matchup Row
                      RowLayout {
                        width: parent.width
                        spacing: Style.space(12)

                        // Home Team
                        RowLayout {
                          Layout.fillWidth: true
                          Image {
                            source: liveCard.modelData.home.logo || ""
                            sourceSize.width: 28
                            sourceSize.height: 28
                            visible: source != ""
                          }
                          Text {
                            text: liveCard.modelData.home.name
                            color: root.fg
                            font.bold: true
                            font.family: root.fFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                          }
                          Item { Layout.fillWidth: true }
                          Text {
                            text: liveCard.modelData.home.score
                            color: root.fg
                            font.bold: true
                            font.family: root.fFamily
                            font.pixelSize: Style.font.heading
                          }
                        }

                        Text {
                          text: "vs"
                          color: root.dimFg
                          font.family: root.fFamily
                          font.pixelSize: Style.font.caption
                        }

                        // Away Team
                        RowLayout {
                          Layout.fillWidth: true
                          Text {
                            text: liveCard.modelData.away.score
                            color: root.fg
                            font.bold: true
                            font.family: root.fFamily
                            font.pixelSize: Style.font.heading
                          }
                          Item { Layout.fillWidth: true }
                          Text {
                            text: liveCard.modelData.away.name
                            color: root.fg
                            font.bold: true
                            font.family: root.fFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                          }
                          Image {
                            source: liveCard.modelData.away.logo || ""
                            sourceSize.width: 28
                            sourceSize.height: 28
                            visible: source != ""
                          }
                        }
                      }
                    }
                  }
                }
              }

              // Recent Results Section
              Column {
                width: parent.width
                spacing: Style.space(8)

                PanelSectionHeader {
                  text: "RECENT RESULTS"
                  foreground: root.fg
                  fontFamily: root.fFamily
                }

                Text {
                  visible: !root.nblData || !root.nblData.recent_games || root.nblData.recent_games.length === 0
                  text: "No recent match results available."
                  color: root.dimFg
                  font.family: root.fFamily
                  font.pixelSize: Style.font.body
                }

                Repeater {
                  model: root.nblData ? (root.nblData.recent_games || []) : []
                  delegate: Rectangle {
                    id: matchCard
                    required property var modelData
                    width: parent.width
                    implicitHeight: matchCol.implicitHeight + Style.space(16)
                    radius: 8
                    color: root.cardBg
                    border.color: root.cardBorder
                    border.width: 1

                    Column {
                      id: matchCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.space(8)
                      spacing: Style.space(6)

                      // Header row: Date & status
                      RowLayout {
                        width: parent.width
                        Text {
                          text: matchCard.modelData.date_str + " • " + matchCard.modelData.status_detail
                          color: root.dimFg
                          font.family: root.fFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                          text: matchCard.modelData.venue
                          color: root.dimFg
                          font.family: root.fFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }

                      // Home Team Row
                      RowLayout {
                        width: parent.width
                        spacing: Style.space(8)

                        Image {
                          source: matchCard.modelData.home.logo || ""
                          sourceSize.width: 22
                          sourceSize.height: 22
                          visible: source != ""
                        }

                        Text {
                          text: matchCard.modelData.home.name
                          color: matchCard.modelData.home.winner ? root.fg : root.dimFg
                          font.family: root.fFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: matchCard.modelData.home.winner
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }

                        Text {
                          text: matchCard.modelData.home.score
                          color: matchCard.modelData.home.winner ? root.fg : root.dimFg
                          font.family: root.fFamily
                          font.pixelSize: Style.font.body
                          font.bold: matchCard.modelData.home.winner
                        }
                      }

                      // Away Team Row
                      RowLayout {
                        width: parent.width
                        spacing: Style.space(8)

                        Image {
                          source: matchCard.modelData.away.logo || ""
                          sourceSize.width: 22
                          sourceSize.height: 22
                          visible: source != ""
                        }

                        Text {
                          text: matchCard.modelData.away.name
                          color: matchCard.modelData.away.winner ? root.fg : root.dimFg
                          font.family: root.fFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: matchCard.modelData.away.winner
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }

                        Text {
                          text: matchCard.modelData.away.score
                          color: matchCard.modelData.away.winner ? root.fg : root.dimFg
                          font.family: root.fFamily
                          font.pixelSize: Style.font.body
                          font.bold: matchCard.modelData.away.winner
                        }
                      }
                    }
                  }
                }
              }
            }

            // ==================== TAB 2: SCHEDULE ====================
            Column {
              id: scheduleTab
              visible: root.activeTab === "schedule"
              width: parent.width
              spacing: Style.space(10)

              PanelSectionHeader {
                text: "UPCOMING FIXTURES"
                foreground: root.fg
                fontFamily: root.fFamily
              }

              Text {
                visible: !root.nblData || !root.nblData.upcoming_games || root.nblData.upcoming_games.length === 0
                text: "No upcoming games scheduled in the next 14 days."
                color: root.dimFg
                font.family: root.fFamily
                font.pixelSize: Style.font.body
              }

              Repeater {
                model: root.nblData ? (root.nblData.upcoming_games || []) : []
                delegate: Rectangle {
                  id: schedCard
                  required property var modelData
                  width: parent.width
                  implicitHeight: schedCol.implicitHeight + Style.space(16)
                  radius: 8
                  color: root.cardBg
                  border.color: root.cardBorder
                  border.width: 1

                  Column {
                    id: schedCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(8)
                    spacing: Style.space(6)

                    // Date & Time Banner
                    RowLayout {
                      width: parent.width
                      Rectangle {
                        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                        radius: 4
                        implicitWidth: dateBadgeText.implicitWidth + Style.space(8)
                        implicitHeight: dateBadgeText.implicitHeight + Style.space(4)
                        Text {
                          id: dateBadgeText
                          anchors.centerIn: parent
                          text: schedCard.modelData.date_str + " • " + schedCard.modelData.time_str
                          color: Color.accent
                          font.bold: true
                          font.family: root.fFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                      Item { Layout.fillWidth: true }
                      Text {
                        text: schedCard.modelData.venue
                        color: root.dimFg
                        font.family: root.fFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    // Home Team vs Away Team
                    RowLayout {
                      width: parent.width
                      spacing: Style.space(8)

                      Image {
                        source: schedCard.modelData.home.logo || ""
                        sourceSize.width: 22
                        sourceSize.height: 22
                        visible: source != ""
                      }

                      Text {
                        text: schedCard.modelData.home.name + (schedCard.modelData.home.record ? (" (" + schedCard.modelData.home.record + ")") : "")
                        color: root.fg
                        font.family: root.fFamily
                        font.pixelSize: Style.font.bodySmall
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                      }

                      Text {
                        text: "vs"
                        color: root.dimFg
                        font.family: root.fFamily
                        font.pixelSize: Style.font.caption
                      }

                      Image {
                        source: schedCard.modelData.away.logo || ""
                        sourceSize.width: 22
                        sourceSize.height: 22
                        visible: source != ""
                      }

                      Text {
                        text: schedCard.modelData.away.name + (schedCard.modelData.away.record ? (" (" + schedCard.modelData.away.record + ")") : "")
                        color: root.fg
                        font.family: root.fFamily
                        font.pixelSize: Style.font.bodySmall
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                      }
                    }
                  }
                }
              }
            }

            // ==================== TAB 3: STANDINGS ====================
            Column {
              id: standingsTab
              visible: root.activeTab === "standings"
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "NBL LADDER (REGULAR SEASON)"
                foreground: root.fg
                fontFamily: root.fFamily
              }

              // Ladder Table Header
              Rectangle {
                width: parent.width
                height: Style.space(26)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
                radius: 4

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)

                  Text {
                    text: "#"
                    width: 24
                    color: root.dimFg
                    font.family: root.fFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    text: "TEAM"
                    Layout.fillWidth: true
                    color: root.dimFg
                    font.family: root.fFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    text: "W"
                    width: 26
                    horizontalAlignment: Text.AlignRight
                    color: root.dimFg
                    font.family: root.fFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    text: "L"
                    width: 26
                    horizontalAlignment: Text.AlignRight
                    color: root.dimFg
                    font.family: root.fFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    text: "PCT"
                    width: 44
                    horizontalAlignment: Text.AlignRight
                    color: root.dimFg
                    font.family: root.fFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    text: "DIFF"
                    width: 38
                    horizontalAlignment: Text.AlignRight
                    color: root.dimFg
                    font.family: root.fFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    text: "STRK"
                    width: 38
                    horizontalAlignment: Text.AlignRight
                    color: root.dimFg
                    font.family: root.fFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }

              // Standings Rows
              Repeater {
                model: root.nblData ? (root.nblData.standings || []) : []
                delegate: Rectangle {
                  id: standRow
                  required property var modelData
                  required property int index
                  width: parent.width
                  height: Style.space(32)
                  radius: 4
                  color: (standRow.index < 6) ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.04) : "transparent"

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                      text: String(standRow.modelData.rank)
                      width: 24
                      color: (standRow.modelData.rank <= 6) ? Color.accent : root.dimFg
                      font.bold: standRow.modelData.rank <= 6
                      font.family: root.fFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Image {
                      source: standRow.modelData.logo || ""
                      sourceSize.width: 18
                      sourceSize.height: 18
                      visible: source != ""
                    }

                    Text {
                      text: standRow.modelData.team
                      Layout.fillWidth: true
                      color: root.fg
                      font.family: root.fFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: standRow.modelData.rank <= 6
                      elide: Text.ElideRight
                    }

                    Text {
                      text: standRow.modelData.wins
                      width: 26
                      horizontalAlignment: Text.AlignRight
                      color: root.fg
                      font.family: root.fFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      text: standRow.modelData.losses
                      width: 26
                      horizontalAlignment: Text.AlignRight
                      color: root.dimFg
                      font.family: root.fFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      text: standRow.modelData.win_pct
                      width: 44
                      horizontalAlignment: Text.AlignRight
                      color: root.fg
                      font.family: root.fFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      text: standRow.modelData.diff
                      width: 38
                      horizontalAlignment: Text.AlignRight
                      color: standRow.modelData.diff.startsWith("+") ? Color.accent : (standRow.modelData.diff.startsWith("-") ? Color.urgent : root.dimFg)
                      font.family: root.fFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      text: standRow.modelData.streak
                      width: 38
                      horizontalAlignment: Text.AlignRight
                      color: standRow.modelData.streak.startsWith("W") ? Color.accent : root.dimFg
                      font.bold: standRow.modelData.streak.startsWith("W")
                      font.family: root.fFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }

              Text {
                text: "Top 6 qualify for the NBL finals series."
                color: root.dimFg
                font.family: root.fFamily
                font.pixelSize: Style.font.caption
                topPadding: Style.space(4)
              }
            }
          }
        }
      }
    }
  }
}