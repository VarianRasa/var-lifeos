import assert from 'node:assert/strict';
import test from 'node:test';

import {normalize, parseVtt, parseWords} from '../src/index.js';

test('parseVtt converts timestamps to milliseconds', () => {
  assert.deepEqual(
    parseVtt('WEBVTT\n\n00:01.250 --> 00:02.500\nHello world\n'),
    [
      {
        id: 'segment-1',
        startMilliseconds: 1250,
        endMilliseconds: 2500,
        text: 'Hello world',
      },
    ],
  );
});

test('normalize returns Whisper text and timestamp segments', () => {
  assert.deepEqual(
    normalize({
      text: 'Hello world',
      vtt: 'WEBVTT\n\n00:01.250 --> 00:02.500\nHello world\n',
    }),
    {
      text: 'Hello world',
      segments: [
        {
          id: 'segment-1',
          startMilliseconds: 1250,
          endMilliseconds: 2500,
          text: 'Hello world',
        },
      ],
    },
  );
});

test('parseWords groups timestamped words into readable sections', () => {
  assert.deepEqual(
    parseWords([
      {word: 'Hello', start: 0, end: 0.4},
      {word: 'world.', start: 0.45, end: 0.9},
      {word: 'Next', start: 1.8, end: 2.1},
      {word: 'section', start: 2.15, end: 2.6},
    ]),
    [
      {
        id: 'segment-1',
        startMilliseconds: 0,
        endMilliseconds: 900,
        text: 'Hello world.',
      },
      {
        id: 'segment-2',
        startMilliseconds: 1800,
        endMilliseconds: 2600,
        text: 'Next section',
      },
    ],
  );
});
