// The demo's sample project and its scripted sessions. record.mjs plays these against the mock model.
export const DEMO_DIRECTORY = '/Users/Shared/trailhead';

export const PROJECT_FILES = {
  'README.md': `# Trailhead

A small HTTP API that signs hikers up for guided trail walks.

## Running

\`\`\`sh
npm install
npm start
\`\`\`

The server listens on port 8080. \`POST /signup\` takes a name, an email address and a trail.
`,
  'package.json': `{
  "name": "trailhead",
  "version": "0.3.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node src/server.ts",
    "test": "node --test test/"
  }
}
`,
  'src/server.ts': `import { createServer } from "node:http";
import { config } from "./config.ts";
import { signup } from "./routes/signup.ts";

const server = createServer(async (request, response) => {
  if (request.method === "POST" && request.url === "/signup") return signup(request, response);
  response.writeHead(404).end();
});

server.listen(config.port, () => console.log(\`Listening on \${config.port}\`));
`,
  'src/config.ts': `export const config = {
  port: 8080,
  trails: ["Ridge Loop", "Cedar Falls", "Lakeshore"],
};
`,
  'src/routes/signup.ts': `import type { IncomingMessage, ServerResponse } from "node:http";

export async function signup(request: IncomingMessage, response: ServerResponse) {
  const body = JSON.parse(await text(request));
  response.writeHead(201, { "content-type": "application/json" });
  response.end(JSON.stringify({ name: body.name, trail: body.trail }));
}

async function text(request: IncomingMessage) {
  let data = "";
  for await (const chunk of request) data += chunk;
  return data;
}
`,
  'test/signup.test.ts': `import assert from "node:assert/strict";
import test from "node:test";

test("signs a hiker up", async () => {
  const response = await fetch("http://localhost:8080/signup", { method: "POST", body: JSON.stringify({ name: "Ada", email: "ada@example.com", trail: "Ridge Loop" }) });
  assert.equal(response.status, 201);
});
`,
};

/** Uncommitted work in the project, so the review shows a working-tree diff. */
export const WORKING_CHANGES = {
  'src/validate.ts': `const EMAIL = /^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$/;

export function validateSignup(body: { name?: string; email?: string; trail?: string }, trails: string[]) {
  const problems: string[] = [];
  if (!body.name?.trim()) problems.push("Name is required.");
  if (!body.email || !EMAIL.test(body.email)) problems.push("Email address is not valid.");
  if (!body.trail || !trails.includes(body.trail)) problems.push("Choose one of the listed trails.");
  return problems;
}
`,
  'src/routes/signup.ts': `import type { IncomingMessage, ServerResponse } from "node:http";
import { config } from "../config.ts";
import { validateSignup } from "../validate.ts";

export async function signup(request: IncomingMessage, response: ServerResponse) {
  const body = JSON.parse(await text(request));
  const problems = validateSignup(body, config.trails);
  if (problems.length) {
    response.writeHead(422, { "content-type": "application/json" });
    return response.end(JSON.stringify({ problems }));
  }
  response.writeHead(201, { "content-type": "application/json" });
  response.end(JSON.stringify({ name: body.name, trail: body.trail }));
}

async function text(request: IncomingMessage) {
  let data = "";
  for await (const chunk of request) data += chunk;
  return data;
}
`,
};

const text = (...deltas) => ({ deltas: deltas.map(text => ({ text })) });
const tool = (name, args) => ({ tools: [{ name, arguments: args }] });
const words = (sentence, delayMs = 60) => ({ deltas: sentence.match(/\S+\s*/g).map(text => ({ text, delayMs })) });

// A long working session: quick checks first, so the app pages its history, then a comparison with a table.
const CHECKS = [
  ['Is the email check case-insensitive?', 'Yes: `validate` lowercases the address before it checks the domain.'],
  ['What happens with an empty name?', 'It is reported as `name: required`.'],
  ['And a name made only of spaces?', 'Trimmed first, so it is also `name: required`.'],
  ['Do we cap the name length?', 'At 80 characters, reported as `name: too long`.'],
  ['Which trails are valid?', 'The ids in `config.trails`: `ridge`, `lakeshore` and `canyon`.'],
  ['Is the trail id case-sensitive?', 'Yes, ids are matched exactly.'],
  ['What status does a bad request get?', '422, with the list of problems in the body.'],
  ['And malformed JSON?', '400, before validation runs.'],
  ['Does the route still answer 201 on success?', 'Yes, with the booking.'],
  ['Are problems reported all at once?', 'Yes, every problem in one response.'],
  ['Is the order of problems stable?', 'Name, email, then trail.'],
  ['Do we validate the date?', 'Not yet; the request has no date field.'],
  ['Could someone book the same trail twice?', 'Yes. That is a booking rule, not validation.'],
  ['Does the test cover a bad email?', 'Not yet; I will add it with the others.'],
  ['How long does validation take?', 'Well under a millisecond per request.'],
  ['Any new dependencies?', 'None so far.'],
  ['Does it work on Node 20?', 'Yes, it only uses the standard library.'],
  ['Is `validate` exported for reuse?', 'Yes, from `src/validate.ts`.'],
  ['Does it mutate the input?', 'No, it only reads it.'],
  ['What about extra fields?', 'They are ignored.'],
  ['Should extra fields be an error?', 'Ignoring them keeps older clients working, so I would leave it.'],
  ['Is the error text user-facing?', 'It is meant for the client to map to its own wording.'],
  ['Can the client tell fields apart?', 'Each problem names its field.'],
  ['Are trails loaded once?', 'Yes, at startup from `config.ts`.'],
  ['Anything else to check before we pick a library?', 'No, the rules are settled.'],
];

/**
 * kind: "done" is finished history; "live" streams when it is first opened; "permission" and "form" wait for
 * an answer in the demo, then stream the rest.
 */
export const SESSIONS = [
  {
    kind: 'done', title: 'Explain the project layout', prompt: 'Give me a quick tour of this project.',
    script: { calls: [tool('read', { path: 'README.md' }), tool('glob', { pattern: 'src/**/*.ts' }), text(
      'Trailhead is a small Node HTTP API for guided trail walk sign-ups.\n\n',
      '- `src/server.ts` starts the server and routes `POST /signup`.\n',
      '- `src/routes/signup.ts` parses the request and answers with the booking.\n',
      '- `src/config.ts` holds the port and the list of trails.\n',
      '- `test/signup.test.ts` checks a sign-up end to end.\n\n',
      'The sign-up route trusts its input today, so validation is the obvious next step.')] },
  },
  {
    kind: 'done', title: 'Run the test suite', prompt: 'Run the tests and tell me what fails.',
    script: { calls: [tool('shell', { command: "printf '✔ signs a hiker up (41ms)\\nℹ tests 1\\nℹ pass 1\\nℹ fail 0\\n'" }), text('All 1 test passes. Coverage of invalid input is missing: nothing posts a bad email address yet.')] },
  },
  {
    kind: 'done', title: 'Investigate slow sign-ups', prompt: 'Sign-ups feel slow under load. Can you find out why?',
    script: { calls: [
      tool('subagent', { agent: 'general', prompt: 'Read src/routes/signup.ts and report anything that blocks the event loop.', description: 'Check the sign-up route' }),
      text('The route reads the body in one string and parses it at the end. Nothing blocks the event loop.'),
      text('The route itself is fine. The slowness is more likely the single-threaded test server; I would measure with real load before changing code.'),
    ] },
  },
  {
    kind: 'done', title: 'Compare validation libraries', history: CHECKS.map(([prompt]) => ({ prompt })),
    prompt: 'Compare the options for validating the sign-up request.',
    script: { calls: [...CHECKS.map(([, reply]) => text(reply)), text(
      'Three options fit a route this small:\n\n',
      '| Option | Size | Types | Errors |\n',
      '| --- | --- | --- | --- |\n',
      '| Hand-written | None | Manual | Our own list |\n',
      '| Zod | Larger | Inferred | Path and message |\n',
      '| Valibot | Small | Inferred | Path and message |\n\n',
      'For three fields the hand-written check is enough, and it keeps the project free of dependencies:\n\n',
      '```ts\n',
      'export function validate(body: SignUp): Problem[] {\n',
      '  const problems: Problem[] = [];\n',
      '  if (!body.name?.trim()) problems.push({ field: "name", code: "required" });\n',
      '  if (!/^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$/.test(body.email ?? "")) problems.push({ field: "email", code: "invalid" });\n',
      '  if (!config.trails.includes(body.trail)) problems.push({ field: "trail", code: "unknown" });\n',
      '  return problems;\n',
      '}\n',
      '```\n\n',
      'If the request grows past a handful of fields, Valibot gives the same kind of errors in a smaller bundle.')] },
  },
  {
    kind: 'live', title: 'Add input validation to sign-up', prompt: 'Validate the sign-up request: name, email and a known trail.',
    script: { calls: [
      tool('read', { path: 'src/routes/signup.ts' }),
      tool('grep', { pattern: 'trails', path: 'src' }),
      words('I read the route and the config. The request body goes straight into the booking, so a missing name or a typo in the email address is accepted today. '),
      words('I added `src/validate.ts`, which returns a list of problems, and the route now answers 422 with that list when anything is wrong. '),
      words('Next I would add tests for each rule: an empty name, an email without a domain, and a trail that is not in the config.'),
    ] },
  },
  {
    kind: 'permission', title: 'Read the port from the environment', prompt: 'Let the port come from the PORT environment variable.',
    script: { calls: [
      tool('read', { path: 'src/config.ts' }),
      tool('edit', { path: 'src/config.ts', oldString: '  port: 8080,', newString: '  port: Number(process.env.PORT ?? 8080),' }),
      text('Done: the server now listens on `PORT` when it is set, and on 8080 otherwise.'),
    ] },
  },
  {
    kind: 'form', title: 'Choose a log format', prompt: 'Add request logging.', answer: { q0: 'JSON lines' },
    script: { calls: [
      tool('question', { questions: [{ header: 'Format', question: 'How should request logs be written?', options: [
        { label: 'JSON lines', description: 'One JSON object per request, easy to search' },
        { label: 'Plain text', description: 'Readable in a terminal' },
      ] }] }),
      text('I will log one JSON object per request, with the method, path, status and duration.'),
    ] },
  },
];
