import fc from "fast-check";

// The only place where the seed lives: tests never pass their own. A failure prints its seed;
// reproduce it with FC_SEED=<seed> npm test -w @oam/sdk.
const seed = process.env.FC_SEED === undefined ? undefined : Number(process.env.FC_SEED);

fc.configureGlobal({ ...(seed === undefined ? {} : { seed }), numRuns: 200 });
