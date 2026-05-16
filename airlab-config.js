// ============================================================
// airlab-config.js — Shared Supabase config
// ============================================================

const SUPABASE_URL  = 'https://rbyidedznycpmudrnumo.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJieWlkZWR6bnljcG11ZHJudW1vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NDk3MDcsImV4cCI6MjA5NDAyNTcwN30.wRRM3qv7KN-6Nu2eamrSoPQ7xK6kJmCfSNvbTzi6zfg';

function calcIAQScore({ co2, pm25, tvoc, humidity, temperature }) {
  let score = 100;
  if (co2 > 2000) score -= 35; else if (co2 > 1500) score -= 22; else if (co2 > 1000) score -= 12; else if (co2 > 800) score -= 5;
  if (pm25 > 35) score -= 30; else if (pm25 > 25) score -= 18; else if (pm25 > 15) score -= 8;
  if (tvoc > 1.0) score -= 20; else if (tvoc > 0.6) score -= 12; else if (tvoc > 0.3) score -= 5;
  if (humidity < 20 || humidity > 80) score -= 15; else if (humidity < 30 || humidity > 70) score -= 8; else if (humidity < 40 || humidity > 60) score -= 3;
  if (temperature < 16 || temperature > 30) score -= 10; else if (temperature < 18 || temperature > 28) score -= 5; else if (temperature < 20 || temperature > 26) score -= 2;
  score = Math.max(0, Math.min(100, Math.round(score)));
  const grade = score >= 85 ? 'SHKËLQYER' : score >= 70 ? 'MIRË' : score >= 55 ? 'MESATAR' : 'DOBËT';
  return { score, grade };
}

function generateAnalysis({ co2, pm25, tvoc, humidity, temperature, grade }) {
  const issues = [], recs = [];
  if (co2 > 1500) { issues.push('CO₂ në nivel kritik'); recs.push('HRV/ERV i detyrueshëm'); }
  else if (co2 > 1000) { issues.push('CO₂ mbi kufirin ASHRAE'); recs.push('rritni ventilimin'); }
  if (pm25 > 25) { issues.push('PM2.5 mbi kufirin WHO'); recs.push('instaloni filtra HEPA'); }
  else if (pm25 > 15) { issues.push('PM2.5 në nivel kufiri'); recs.push('monitorim i rregullt'); }
  if (tvoc > 0.6) { issues.push('TVOC i ngritur'); recs.push('verifikoni materialet e brendshme'); }
  if (humidity < 30) { issues.push('lagështia shumë e ulët'); recs.push('humidifikator'); }
  if (humidity > 70) { issues.push('lagështia shumë e lartë'); recs.push('ventilim shtesë'); }
  if (temperature > 26) recs.push('rregulloni termostat');
  if (temperature < 18) recs.push('rritni ngrohjen');
  if (issues.length === 0) return `Cilësia e ajrit është ${grade.toLowerCase()}. Parametrat brenda normave ASHRAE/WHO. Rekomandohet monitorim periodik.`;
  return `Probleme: ${issues.join(', ')}. Rekomandime: ${recs.join('; ')}.`;
}

function formatDate(dateStr) {
  const months = ['Janar','Shkurt','Mars','Prill','Maj','Qershor','Korrik','Gusht','Shtator','Tetor','Nëntor','Dhjetor'];
  const d = new Date(dateStr);
  return `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
}

function scoreColor(s) {
  if (s >= 85) return '#3ecf8e';
  if (s >= 70) return '#4ea8e0';
  if (s >= 55) return '#e0c052';
  return '#e05252';
}
