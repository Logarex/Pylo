// Robot Cloudflare (offre gratuite) : chaque minute, regarde si l’ANFR a publié sur data.gouv
// et lance aussitôt le workflow GitHub « Mise à jour ANFR », au lieu d’attendre le cron GitHub
// (souvent décalé de plusieurs heures).

const OBSERVATOIRE = "https://www.data.gouv.fr/api/1/datasets/6ab291cf426d615c84196260/";
const SUPPORTS = "https://www.data.gouv.fr/api/1/datasets/donnees-sur-les-installations-radioelectriques-de-plus-de-5-watts-1/";
const MANIFEST = "https://raw.githubusercontent.com/Logarex/Pylo/main/data/manifest.json";
const REPO = "Logarex/Pylo";
const WORKFLOW = "anfr.yml";
// Pas de nouveau lancement si une exécution a démarré il y a moins de 20 minutes.
const COOLDOWN_MS = 20 * 60 * 1000;

async function getJSON(url) {
  const response = await fetch(url, { headers: { "User-Agent": "pylo-anfr-watcher" }, cf: { cacheTtl: 0 } });
  if (!response.ok) throw new Error(`${url} : HTTP ${response.status}`);
  return response.json();
}

function newest(resources, keep, key) {
  return resources.filter(keep).sort((a, b) => (key(b) > key(a) ? 1 : key(b) < key(a) ? -1 : 0))[0];
}

/// Même calcul que `anfr-import --catalog` (Sources/ANFRImport/Importer.swift).
export async function catalogVersion() {
  const [observatoire, supports] = await Promise.all([getJSON(OBSERVATOIRE), getJSON(SUPPORTS)]);
  const resource = newest(observatoire.resources,
    r => r.url.endsWith(".zip") && r.title.toLowerCase().includes("observatoire"),
    r => r.last_modified ?? r.title);
  const dates = newest(supports.resources,
    r => r.url.endsWith("-data.zip") && r.title.toLowerCase().includes("supports"),
    r => r.last_modified ?? "");
  if (!resource || !dates) throw new Error("Ressources ANFR introuvables sur data.gouv");
  return `${resource.id}:${resource.last_modified ?? resource.title}|${dates.id}:${dates.last_modified ?? dates.title}`;
}

function github(env, path, init = {}) {
  return fetch(`https://api.github.com/repos/${REPO}${path}`, {
    ...init,
    headers: {
      "Authorization": `Bearer ${env.GITHUB_TOKEN}`,
      "Accept": "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "pylo-anfr-watcher",
      ...(init.headers ?? {}),
    },
  });
}

export async function check(env) {
  const [version, manifest] = await Promise.all([catalogVersion(), getJSON(`${MANIFEST}?t=${Date.now()}`)]);
  if (version === manifest.sourceVersion) return { action: "rien", raison: "Pylo a déjà ces données", version };

  const runs = await github(env, `/actions/workflows/${WORKFLOW}/runs?per_page=1`);
  if (!runs.ok) throw new Error(`GitHub : HTTP ${runs.status}`);
  const last = (await runs.json()).workflow_runs?.[0];
  if (last && (last.status !== "completed" || Date.now() - Date.parse(last.created_at) < COOLDOWN_MS)) {
    return { action: "attente", raison: `exécution récente (${last.status})`, version };
  }

  const dispatch = await github(env, `/actions/workflows/${WORKFLOW}/dispatches`, {
    method: "POST",
    body: JSON.stringify({ ref: "main" }),
  });
  if (dispatch.status !== 204) throw new Error(`Lancement GitHub refusé : HTTP ${dispatch.status} ${await dispatch.text()}`);
  return { action: "lancé", raison: "nouvelle publication ANFR", version };
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(check(env).then(r => console.log(JSON.stringify(r)), e => console.error(e.message)));
  },
  // Ouvrir l’adresse du robot dans un navigateur montre l’état actuel, sans rien lancer.
  async fetch() {
    try {
      const [version, manifest] = await Promise.all([catalogVersion(), getJSON(`${MANIFEST}?t=${Date.now()}`)]);
      return Response.json({ data_gouv: version, pylo: manifest.sourceVersion, a_jour: version === manifest.sourceVersion });
    } catch (e) {
      return Response.json({ erreur: e.message }, { status: 502 });
    }
  },
};
