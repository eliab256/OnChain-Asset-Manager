import * as fs from 'fs';
import * as path from 'path';

const OUT_DIR = path.resolve(process.argv[2] || './out');
const SCHEMA_PATH = path.resolve(process.argv[3] || './prisma/schema.prisma');

const TYPE_MAP: Record<string, string> = {
  address: 'String',
  bool: 'Boolean',
  string: 'String',
  bytes: 'String',
};

function mapType(solidityType: string): string {
  if (TYPE_MAP[solidityType]) return TYPE_MAP[solidityType];
  if (solidityType.startsWith('uint') || solidityType.startsWith('int')) return 'String';
  if (solidityType.startsWith('bytes')) return 'String';
  return 'String';
}

function toCamelCase(str: string): string {
  return str.charAt(0).toLowerCase() + str.slice(1);
}

interface AbiInput {
  name: string;
  type: string;
  indexed?: boolean;
}

interface AbiEvent {
  type: string;
  name: string;
  inputs: AbiInput[];
}

function generateModel(eventName: string, inputs: AbiInput[]): string {
  const indexedFields = inputs
    .filter(i => i.indexed)
    .map(i => toCamelCase(i.name));

  const fields = inputs.map(input => {
    const fieldName = toCamelCase(input.name);
    const fieldType = mapType(input.type);
    return `  ${fieldName.padEnd(20)} ${fieldType}`;
  }).join('\n');

  const indexLines = indexedFields.length > 0
    ? `\n  @@index([${indexedFields.join(', ')}])`
    : '';

  return `model ${eventName} {
  id                   Int      @id @default(autoincrement())
${fields}
  blockNumber          BigInt
  txHash               String
  logIndex             Int
  timestamp            DateTime

  @@unique([txHash, logIndex])${indexLines}
}`;
}

function findJsonFiles(dir: string): string[] {
  const results: string[] = [];
  if (!fs.existsSync(dir)) {
    console.error(`Directory not found: ${dir}`);
    process.exit(1);
  }
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...findJsonFiles(fullPath));
    } else if (entry.isFile() && entry.name.endsWith('.json')) {
      results.push(fullPath);
    }
  }
  return results;
}

function extractEvents(jsonPath: string): AbiEvent[] {
  try {
    const raw = fs.readFileSync(jsonPath, 'utf-8');
    const json = JSON.parse(raw);
    if (!Array.isArray(json.abi)) return [];
    return json.abi.filter((item: AbiEvent) => item.type === 'event');
  } catch {
    return [];
  }
}

function main() {
  console.log(`Reading ABIs from: ${OUT_DIR}`);
  console.log(`Appending models to: ${SCHEMA_PATH}`);

  const jsonFiles = findJsonFiles(OUT_DIR);
  const seenEvents = new Set<string>();
  const models: string[] = [];

  for (const file of jsonFiles) {
    const events = extractEvents(file);
    for (const event of events) {
      if (seenEvents.has(event.name)) continue;
      seenEvents.add(event.name);
      models.push(generateModel(event.name, event.inputs));
    }
  }

  if (models.length === 0) {
    console.log('No events found.');
    return;
  }

  if (!fs.existsSync(SCHEMA_PATH)) {
    console.error(`schema.prisma not found at: ${SCHEMA_PATH}`);
    process.exit(1);
  }

  const separator = '\n\n// --- AUTO-GENERATED MODELS --- DO NOT EDIT BELOW THIS LINE ---\n\n';
  let schema = fs.readFileSync(SCHEMA_PATH, 'utf-8');

  // rimuove models generati in precedenza
  const cutIndex = schema.indexOf(separator);
  if (cutIndex !== -1) {
    schema = schema.substring(0, cutIndex);
  }

  const output = schema + separator + models.join('\n\n') + '\n';
  fs.writeFileSync(SCHEMA_PATH, output, 'utf-8');

  console.log(`Done. ${seenEvents.size} models appended:`);
  seenEvents.forEach(name => console.log(`  - ${name}`));
}

main();
