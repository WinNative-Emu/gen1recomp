const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const dependencies = createRequire(path.join(__dirname, 'package.json'));
const {Dex, TeamValidator} = dependencies('@pkmn/sim');
const packageRoot = path.resolve(path.dirname(dependencies.resolve('@pkmn/sim')), '../../..');
const version = JSON.parse(fs.readFileSync(path.join(packageRoot, 'package.json'), 'utf8')).version;

function validate(request) {
  if (version !== '0.10.11') throw new Error('Unexpected simulator version');
  if (!request.generations || Object.keys(request.generations).sort().join(',') !== '1,2,3') throw new Error('Expected three generations');
  let count = 0;
  for (const generation of [1,2,3]) {
    const dex = Dex.forGen(generation), validator = new TeamValidator(`gen${generation}ubers`);
    for (const [species, fields] of Object.entries(request.generations[generation])) {
      const definition = dex.species.get(species);
      if (!definition.exists || definition.gen > generation) throw new Error('Species unavailable in generation');
      const set = {species, ability:generation === 3 ? definition.abilities[0] : 'No Ability',
        nature:'Serious', evs:Object.fromEntries(['hp','atk','def','spa','spd','spe'].map(s=>[s,generation<3?252:0])),
        item:'', ...fields};
      if (new Set(set.moves.map(Dex.toID)).size !== set.moves.length) throw new Error('Duplicate moves');
      if (dex.species.get(set.species).baseSpecies !== definition.baseSpecies) throw new Error('Species override mismatch');
      const errors = validator.validateSet(structuredClone(set));
      if (errors) throw new Error(`Gen ${generation} ${species}: ${errors.join('; ')}`);
      count++;
    }
  }
  return {name:'@pkmn/sim',version,validated:count,scope:'generation singles set legality'};
}
if (require.main === module) {
  try {process.stdout.write(JSON.stringify(validate(JSON.parse(fs.readFileSync(0,'utf8'))))+'\n');}
  catch (error) {process.stderr.write(error.message+'\n');process.exitCode=1;}
}
module.exports = {validate};
