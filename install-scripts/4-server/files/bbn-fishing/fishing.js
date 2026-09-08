(function () {
  const FT = 3.280839895;
  const KTS = 1.943844492;
  const STALE_MS = 15000;
  const history = [];
  const values = {};
  const times = {};
  let settings = {
    shallowAlarmFt: 4,
    shallowAlarmEnabled: false,
    transducerOffsetFt: 0,
    draftFt: 2
  };
  let alarmOn = false;
  let lastBeep = 0;

  function num(path) {
    const v = values[path];
    return typeof v === "number" && Number.isFinite(v) ? v : null;
  }

  function fresh(path) {
    return times[path] && Date.now() - times[path] < STALE_MS;
  }

  function setText(id, text) {
    document.getElementById(id).textContent = text;
  }

  function ftFromM(m) {
    return m * FT;
  }

  function fFromK(k) {
    return (k - 273.15) * 9 / 5 + 32;
  }

  function formatFt(m) {
    if (m === null) return "--";
    return ftFromM(m).toFixed(1);
  }

  function depthSurfaceM() {
    if (fresh("environment.depth.belowSurface")) return num("environment.depth.belowSurface");
    if (fresh("environment.depth.belowTransducer")) {
      return num("environment.depth.belowTransducer") + settings.transducerOffsetFt / FT;
    }
    return null;
  }

  function firstFresh(paths) {
    for (let i = 0; i < paths.length; i++) {
      if (fresh(paths[i]) && num(paths[i]) !== null) return paths[i];
    }
    return null;
  }

  function remember(path, value, ts) {
    if (value === undefined || value === null) return;
    if (typeof value === "object" && value.value !== undefined) value = value.value;
    values[path] = value;
    times[path] = ts || Date.now();
  }

  function applyDelta(delta) {
    const updates = delta.updates || [];
    updates.forEach(function (update) {
      const ts = update.timestamp ? Date.parse(update.timestamp) : Date.now();
      (update.values || []).forEach(function (item) {
        remember(item.path, item.value, ts);
      });
    });
    render();
  }

  function render() {
    const surface = depthSurfaceM();
    const xdcr = fresh("environment.depth.belowTransducer") ? num("environment.depth.belowTransducer") : null;
    const temp = firstFresh([
      "environment.water.temperature",
      "environment.water.temperatureSurface"
    ]);

    if (surface !== null) {
      setText("depth", ftFromM(surface).toFixed(1));
      setText("depthState", "Depth live");
      document.getElementById("depthState").className = "hint";
      if (!history.length || Date.now() - history[history.length - 1].t > 800) {
        history.push({ t: Date.now(), ft: ftFromM(surface) });
      }
      const cut = Date.now() - 60 * 60 * 1000;
      while (history.length && history[0].t < cut) history.shift();
    } else {
      setText("depth", "--");
      setText("depthState", "Depth stale or not connected");
      document.getElementById("depthState").className = "hint stale";
    }
    setText("xdcr", xdcr === null ? "-- ft" : formatFt(xdcr) + " ft");
    setText("temp", temp ? fFromK(num(temp)).toFixed(1) + " F" : "-- F");

    const pos = values["navigation.position"];
    const posOk = fresh("navigation.position") && pos && typeof pos.latitude === "number";
    if (posOk) {
      setText("lat", pos.latitude.toFixed(5));
      setText("lon", pos.longitude.toFixed(5));
      setText("gpsState", "GPS live");
      document.getElementById("gpsState").className = "hint";
    } else {
      setText("lat", "--");
      setText("lon", "--");
      setText("gpsState", "GPS stale or not connected");
      document.getElementById("gpsState").className = "hint stale";
    }

    const sog = fresh("navigation.speedOverGround") ? num("navigation.speedOverGround") : null;
    setText("sog", sog === null ? "-- kn" : (sog * KTS).toFixed(1) + " kn");

    const measured = firstFresh([
      "environment.wind.speedApparent",
      "environment.wind.speedTrue",
      "environment.wind.speedOverGround"
    ]);
    const forecast = firstFresh([
      "environment.forecast.wind.speed",
      "environment.forecast.wind.speedTrue",
      "environment.wind.speedForecast"
    ]);
    if (measured) {
      setText("windLabel", "Wind measured");
      setText("wind", (num(measured) * KTS).toFixed(0) + " kn");
    } else if (forecast) {
      setText("windLabel", "Wind forecast");
      setText("wind", (num(forecast) * KTS).toFixed(0) + " kn");
    } else {
      setText("windLabel", "Wind");
      setText("wind", "not connected");
    }

    const volts = firstFresh(["electrical.batteries.0.voltage", "electrical.batteries.house.voltage"]);
    const amps = firstFresh(["electrical.batteries.0.current", "electrical.batteries.house.current"]);
    const solar = firstFresh([
      "electrical.solar.0.panelPower",
      "electrical.solar.0.power",
      "electrical.solar.house.panelPower"
    ]);
    setText("volts", volts ? num(volts).toFixed(1) + " V" : "not connected");
    setText("amps", amps ? num(amps).toFixed(1) + " A" : "not connected");
    setText("solar", solar ? num(solar).toFixed(0) + " W" : "not connected");

    const shallow = settings.shallowAlarmEnabled && surface !== null && ftFromM(surface) < settings.shallowAlarmFt;
    document.getElementById("alarm").className = shallow ? "banner show" : "banner";
    if (shallow && Date.now() - lastBeep > 5000) {
      lastBeep = Date.now();
      beep();
    }
    alarmOn = shallow;
    draw();
  }

  function draw() {
    const canvas = document.getElementById("history");
    const ctx = canvas.getContext("2d");
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    ctx.strokeStyle = "#1d4a58";
    ctx.beginPath();
    ctx.moveTo(0, h - 24);
    ctx.lineTo(w, h - 24);
    ctx.stroke();
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

  function beep() {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.frequency.value = 880;
      gain.gain.value = 0.08;
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start();
      osc.stop(ctx.currentTime + 0.25);
    } catch (err) {
      /* touch browsers may block audio until a tap */
    }
  }

  function connect() {
    const ws = new WebSocket("ws://127.0.0.1:3000/signalk/v1/stream?subscribe=none");
    ws.onopen = function () {
      ws.send(JSON.stringify({
        context: "vessels.self",
        subscribe: [{ path: "*", period: 1000, policy: "instant" }]
      }));
    };
    ws.onmessage = function (ev) {
      let msg;
      try { msg = JSON.parse(ev.data); } catch (err) { return; }
      if (msg.updates) applyDelta(msg);
    };
    ws.onclose = function () {
      setText("depthState", "Signal K not connected");
      setTimeout(connect, 3000);
    };
  }

  function loadSettings() {
    return fetch("/api/settings").then(function (res) { return res.json(); }).then(function (data) {
      settings = data;
      document.getElementById("alarmFt").value = settings.shallowAlarmFt;
      document.getElementById("offsetFt").value = settings.transducerOffsetFt;
      document.getElementById("alarmToggle").textContent = settings.shallowAlarmEnabled ? "Alarm on" : "Alarm off";
    }).catch(function () {});
  }

  function readForm() {
    settings.shallowAlarmFt = Number(document.getElementById("alarmFt").value) || 4;
    settings.transducerOffsetFt = Number(document.getElementById("offsetFt").value) || 0;
  }

  document.getElementById("alarmToggle").addEventListener("click", function () {
    readForm();
    settings.shallowAlarmEnabled = !settings.shallowAlarmEnabled;
    document.getElementById("alarmToggle").textContent = settings.shallowAlarmEnabled ? "Alarm on" : "Alarm off";
    render();
  });

  document.getElementById("saveSet").addEventListener("click", function () {
    readForm();
    fetch("/api/settings", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(settings)
    }).then(function () {
      document.getElementById("markState").textContent = "Settings saved.";
    });
  });

  document.getElementById("mark").addEventListener("click", function () {
    const pos = values["navigation.position"];
    if (!pos || typeof pos.latitude !== "number" || !fresh("navigation.position")) {
      document.getElementById("markState").textContent = "No live GPS fix. Mark not saved.";
      return;
    }
    const surface = depthSurfaceM();
    const tempPath = firstFresh(["environment.water.temperature", "environment.water.temperatureSurface"]);
    const body = {
      latitude: pos.latitude,
      longitude: pos.longitude,
      depthFt: surface === null ? null : Number(ftFromM(surface).toFixed(1)),
      tempF: tempPath ? Number(fFromK(num(tempPath)).toFixed(1)) : null,
      note: document.getElementById("note").value
    };
    fetch("/api/mark", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    }).then(function (res) { return res.json(); }).then(function (data) {
      document.getElementById("markState").textContent = data.ok
        ? "Marked " + data.name + ". Open the Fishing layer in OpenCPN if it is not already visible."
        : (data.error || "Mark failed");
      document.getElementById("note").value = "";
    }).catch(function () {
      document.getElementById("markState").textContent = "Could not save the mark.";
    });
  });

  loadSettings().then(connect);
  setInterval(render, 1000);
})();
