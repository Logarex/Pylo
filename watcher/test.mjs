// Vérifie que le robot calcule la même version que `anfr-import --catalog`, sans rien lancer.
import { catalogVersion } from "./src/index.js";
const version = await catalogVersion();
const manifest = await (await fetch(`https://raw.githubusercontent.com/Logarex/Pylo/main/data/manifest.json?t=${Date.now()}`)).json();
console.log("data.gouv :", version);
console.log("Pylo      :", manifest.sourceVersion);
console.log(version === manifest.sourceVersion ? "À jour : rien à lancer." : "Différent : le robot lancerait GitHub.");
