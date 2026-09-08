(function () {
  const history = [];
  let settings = { shallowAlarmFt: 4, shallowAlarmEnabled: false, transducerOffsetFt: 0, draftFt: 2 };

  function setText(id, text) {
    const node = document.getElementById(id);
    if (node) node.textContent = text;
  }

  function draw() {
    const canvas = document.getElementById("history");
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    if (history.length < 2) return;
    const minT = history[0].t;
    const maxT = history[history.length - 1].t;
    const span = Math.max(maxT - minT, 1);
    let minD = history[0].ft;
    let maxD = history[0].ft;
    history.forEach(function (p) {
      minD = Math.min(minD, p.ft);
      maxD = Math.max(maxD, p.ft);
    });
    if (maxD - minD < 2) {
      minD -= 1;
      maxD += 1;
    }
    ctx.strokeStyle = "#f0c674";
    ctx.lineWidth = 2;
    ctx.beginPath();
    history.forEach(function (p, i) {
      const x = ((p.t - minT) / span) * (w - 8) + 4;
      const y = h - 28 - ((p.ft - minD) / (maxD - minD)) * (h - 40);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  }

  function render(state) {
    if (state.depthFresh && state.depthFt !== null) {
      setText("depth", Number(state.depthFt).toFixed(1));
      setText("depthState", "Depth live");
      document.getElementById("depthState").className = "hint";
      if (!history.length || Date.now() - history[history.length - 1].t > 800) {
        history.push({ t: Date.now(), ft: state.depthFt });
      }
      const cut = Date.now() - 60 * 60 * 1000;
      while (history.length && history[0].t < cut) history.shift();
    } else {
      setText("depth", "--");
      setText("depthState", state.sk === "live" ? "Depth stale or not connected" : state.sk);
      document.getElementById("depthState").className = "hint stale";
    }
    setText("xdcr", state.xdcrFt === null ? "-- ft" : state.xdcrFt + " ft");
    setText("temp", state.tempF === null ? "-- F" : state.tempF + " F");
    setText("fishLink", state.fishConnected ? "connected" : "not connected");

    if (state.gpsFresh) {
      setText("lat", state.lat);
      setText("lon", state.lon);
      setText("gpsState", "GPS live");
      document.getElementById("gpsState").className = "hint";
    } else {
      setText("lat", "--");
      setText("lon", "--");
      setText("gpsState", "GPS stale or not connected");
      document.getElementById("gpsState").className = "hint stale";
    }
    setText("sog", state.sogKn === null ? "-- kn" : state.sogKn + " kn");
    document.getElementById("alarm").className = state.shallow ? "banner show" : "banner";
    draw();
  }

  function tick() {
    fetch("/api/state").then(function (res) { return res.json(); }).then(render).catch(function () {
      setText("depthState", "Helm service not connected");
    });
  }

  function loadSettings() {
    return fetch("/api/settings").then(function (res) { return res.json(); }).then(function (data) {
      settings = data;
      document.getElementById("alarmFt").value = settings.shallowAlarmFt;
      document.getElementById("offsetFt").value = settings.transducerOffsetFt;
      document.getElementById("draftFt").value = settings.draftFt;
      document.getElementById("alarmToggle").textContent = settings.shallowAlarmEnabled ? "Alarm on" : "Alarm off";
    });
  }

  function readForm() {
    settings.shallowAlarmFt = Number(document.getElementById("alarmFt").value) || 4;
    settings.transducerOffsetFt = Number(document.getElementById("offsetFt").value) || 0;
    settings.draftFt = Number(document.getElementById("draftFt").value) || 0;
  }

  document.getElementById("alarmToggle").addEventListener("click", function () {
    readForm();
    settings.shallowAlarmEnabled = !settings.shallowAlarmEnabled;
    document.getElementById("alarmToggle").textContent = settings.shallowAlarmEnabled ? "Alarm on" : "Alarm off";
  });

  document.getElementById("saveSet").addEventListener("click", function () {
    readForm();
    fetch("/api/settings", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(settings)
    }).then(function () {
      document.getElementById("markState").textContent = "Settings saved. Signal K will pick up the offset after restart.";
    });
  });

  document.getElementById("mark").addEventListener("click", function () {
    fetch("/api/state").then(function (res) { return res.json(); }).then(function (state) {
      if (!state.gpsFresh) {
        document.getElementById("markState").textContent = "No live GPS fix. Mark not saved.";
        return;
      }
      return fetch("/api/mark", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          latitude: state.lat,
          longitude: state.lon,
          depthFt: state.depthFt,
          tempF: state.tempF,
          note: document.getElementById("note").value
        })
      }).then(function (res) { return res.json(); }).then(function (data) {
        document.getElementById("markState").textContent = data.ok
          ? "Marked " + data.name + ". Open the Fishing layer in OpenCPN if it is not already visible."
          : (data.error || "Mark failed");
        document.getElementById("note").value = "";
      });
    });
  });

  loadSettings().then(tick);
  setInterval(tick, 1000);
})();
