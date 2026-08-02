export interface AiRunner {
  run(model: string, inputs: Record<string, unknown>): Promise<unknown>;
}

export interface WorkshopAnalysis {
  summary: string;
  themes: SourceGroup[];
  clusters: SourceGroup[];
  decisions: SourceStatement[];
  actionItems: SourceStatement[];
  risks: SourceStatement[];
  model: string;
  version: string;
}

type SourceGroup = {name: string; sourceIds: string[]};
type SourceStatement = {text: string; sourceIds: string[]};
type Sticky = {id: string; text: string; votes: number; locale: string};
type JsonObject = Record<string, unknown>;

const model = '@cf/meta/llama-3.1-8b-instruct-fast';
const version = '1';
const maxBodyBytes = 1024 * 1024;
const stickyKeys = new Set(['id', 'text', 'votes', 'locale']);

const outputSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    summary: {type: 'string'},
    themes: {type: 'array', items: sourceGroupSchema('name')},
    clusters: {type: 'array', items: sourceGroupSchema('name')},
    decisions: {type: 'array', items: sourceGroupSchema('text')},
    actionItems: {type: 'array', items: sourceGroupSchema('text')},
    risks: {type: 'array', items: sourceGroupSchema('text')},
  },
  required: ['summary', 'themes', 'clusters', 'decisions', 'actionItems', 'risks'],
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env.AI);
  },
} satisfies ExportedHandler<Env>;

export async function handleRequest(request: Request, ai: AiRunner): Promise<Response> {
  if (new URL(request.url).pathname !== '/analyze') {
    return failure(404, 'not-found', 'Route not found.');
  }
  if (request.method !== 'POST') {
    return failure(405, 'method-not-allowed', 'Only POST is supported.');
  }
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) {
    return failure(415, 'unsupported-media-type', 'Content-Type must be application/json.');
  }
  const contentLength = Number(request.headers.get('Content-Length') ?? '0');
  if (Number.isFinite(contentLength) && contentLength > maxBodyBytes) {
    return failure(413, 'payload-too-large', 'Request body is too large.');
  }

  let value: unknown;
  try {
    value = await request.json();
  } catch {
    return failure(400, 'invalid-json', 'Request body must be valid JSON.');
  }

  try {
    const sticky = parseInput(value);
    const response = await ai.run(model, {
      messages: [
        {
          role: 'system',
          content: 'Analyze workshop sticky notes. Use requested locale where possible. Base every theme, cluster, decision, action item, and risk only on supplied notes. Cite exact source IDs. Never invent IDs.',
        },
        {role: 'user', content: JSON.stringify({sticky})},
      ],
      response_format: {type: 'json_schema', json_schema: outputSchema},
    });
    const analysis = parseModelResponse(response, new Set(sticky.map((item) => item.id)));
    return Response.json({...analysis, model, version} satisfies WorkshopAnalysis);
  } catch (cause) {
    if (cause instanceof InputError) {
      return failure(400, 'invalid-input', cause.message);
    }
    if (cause instanceof ModelResponseError) {
      return failure(502, 'invalid-model-response', 'Model returned invalid structured output.');
    }
    console.error(JSON.stringify({message: 'workshop analysis failed', error: errorMessage(cause)}));
    return failure(503, 'ai-unavailable', 'Workshop analysis is temporarily unavailable.');
  }
}

class InputError extends Error {}
class ModelResponseError extends Error {}

function parseInput(value: unknown): Sticky[] {
  const body = inputRecord(value, 'body');
  if (Object.keys(body).length !== 1 || !Object.hasOwn(body, 'sticky')) {
    throw new InputError('body must contain only sticky.');
  }
  if (!Array.isArray(body.sticky) || body.sticky.length < 1 || body.sticky.length > 300) {
    throw new InputError('sticky must contain 1 to 300 items.');
  }
  const ids = new Set<string>();
  return body.sticky.map((value, index) => {
    const item = inputRecord(value, `sticky[${index}]`);
    if (Object.keys(item).some((key) => !stickyKeys.has(key)) || Object.keys(item).length !== 4) {
      throw new InputError(`sticky[${index}] may contain only id, text, votes, locale.`);
    }
    const id = boundedText(item.id, `sticky[${index}].id`, 1, 100);
    if (ids.has(id)) throw new InputError(`sticky[${index}].id must be unique.`);
    ids.add(id);
    const text = boundedText(item.text, `sticky[${index}].text`, 1, 4000);
    const locale = boundedText(item.locale, `sticky[${index}].locale`, 2, 35);
    if (!Number.isInteger(item.votes) || (item.votes as number) < 0 || (item.votes as number) > 1000000) {
      throw new InputError(`sticky[${index}].votes must be an integer from 0 to 1000000.`);
    }
    return {id, text, votes: item.votes as number, locale};
  });
}

function parseModelResponse(value: unknown, ids: Set<string>): Omit<WorkshopAnalysis, 'model' | 'version'> {
  try {
    const envelope = outputRecord(value);
    const body = outputRecord(envelope.response);
    return {
      summary: outputText(body.summary),
      themes: outputGroups(body.themes, 'name', ids),
      clusters: outputGroups(body.clusters, 'name', ids),
      decisions: outputGroups(body.decisions, 'text', ids),
      actionItems: outputGroups(body.actionItems, 'text', ids),
      risks: outputGroups(body.risks, 'text', ids),
    };
  } catch {
    throw new ModelResponseError();
  }
}

function outputGroups(value: unknown, label: 'name', ids: Set<string>): SourceGroup[];
function outputGroups(value: unknown, label: 'text', ids: Set<string>): SourceStatement[];
function outputGroups(value: unknown, label: 'name' | 'text', ids: Set<string>): Array<SourceGroup | SourceStatement> {
  if (!Array.isArray(value) || value.length > 300) throw new ModelResponseError();
  return value.map((entry) => {
    const item = outputRecord(entry);
    const sourceIds = Array.isArray(item.sourceIds)
      ? item.sourceIds.map(outputText)
      : (() => { throw new ModelResponseError(); })();
    if (sourceIds.length === 0 || sourceIds.some((id) => !ids.has(id))) throw new ModelResponseError();
    return label === 'name'
      ? {name: outputText(item.name), sourceIds}
      : {text: outputText(item.text), sourceIds};
  });
}

function sourceGroupSchema(label: 'name' | 'text'): JsonObject {
  return {
    type: 'object',
    additionalProperties: false,
    properties: {
      [label]: {type: 'string'},
      sourceIds: {type: 'array', items: {type: 'string'}, minItems: 1},
    },
    required: [label, 'sourceIds'],
  };
}

function inputRecord(value: unknown, name: string): JsonObject {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new InputError(`${name} must be an object.`);
  return value as JsonObject;
}
function outputRecord(value: unknown): JsonObject {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new ModelResponseError();
  return value as JsonObject;
}
function boundedText(value: unknown, name: string, min: number, max: number): string {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text.length < min || text.length > max) throw new InputError(`${name} must contain ${min} to ${max} characters.`);
  return text;
}
function outputText(value: unknown): string {
  if (typeof value !== 'string' || !value.trim()) throw new ModelResponseError();
  return value.trim();
}
function errorMessage(value: unknown): string {
  return value instanceof Error ? value.message : String(value);
}
function failure(status: number, code: string, message: string): Response {
  return Response.json({error: {code, message}}, {status});
}
