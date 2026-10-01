/**
 * DuoChat Heartbeat Share Web Audio & Vibration API Helper
 * Generates soft synthesised lub-dub heartbeat sound (Web Audio API)
 * and triggers vibration patterns (navigator.vibrate API).
 */
(function () {
  let audioCtx = null;
  let isMuted = false;

  function initAudio() {
    try {
      if (!audioCtx) {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        if (AudioContextClass) {
          audioCtx = new AudioContextClass();
        }
      }
      if (audioCtx && audioCtx.state === 'suspended') {
        audioCtx.resume();
      }
    } catch (e) {
      console.warn('[Heartbeat Audio] Init warning:', e);
    }
  }

  function playBeat(beatType) {
    if (isMuted) return;
    try {
      initAudio();
      if (!audioCtx) return;

      const now = audioCtx.currentTime;
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();

      osc.type = 'sine';

      // 'lub' is deeper frequency (~55Hz), 'dub' is slightly higher (~85Hz)
      const freq = beatType === 'dub' ? 85 : 55;
      const duration = beatType === 'dub' ? 0.08 : 0.12;

      osc.frequency.setValueAtTime(freq, now);
      osc.frequency.exponentialRampToValueAtTime(25, now + duration);

      gain.gain.setValueAtTime(0.6, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + duration);

      osc.connect(gain);
      gain.connect(audioCtx.destination);

      osc.start(now);
      osc.stop(now + duration);
    } catch (e) {
      console.warn('[Heartbeat Audio] Play beat error:', e);
    }
  }

  function triggerVibration(pattern) {
    try {
      if (typeof navigator !== 'undefined' && navigator.vibrate) {
        navigator.vibrate(pattern || [60, 80, 60, 600]);
      }
    } catch (e) {
      console.warn('[Heartbeat Vibration] Unsupported or blocked:', e);
    }
  }

  function stopVibration() {
    try {
      if (typeof navigator !== 'undefined' && navigator.vibrate) {
        navigator.vibrate(0);
      }
    } catch (e) {}
  }

  function setMuted(muted) {
    isMuted = !!muted;
  }

  function getMuted() {
    return isMuted;
  }

  window.DuoHeartbeat = {
    playBeat: playBeat,
    vibrate: triggerVibration,
    stopVibrate: stopVibration,
    setMuted: setMuted,
    getMuted: getMuted,
  };
})();
