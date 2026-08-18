import { createHmac, randomBytes, scrypt, timingSafeEqual, type ScryptOptions } from 'node:crypto';

const PASSWORD_FORMAT = 'scrypt';
const PASSWORD_VERSION = '1';
const SCRYPT_KEY_LENGTH = 64;
const SCRYPT_SALT_BYTES = 16;

const SCRYPT_OPTIONS: ScryptOptions = {
  N: 16384,
  p: 1,
  r: 8,
  maxmem: 64 * 1024 * 1024,
};

function derivePasswordKey(password: string, salt: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(password, salt, SCRYPT_KEY_LENGTH, SCRYPT_OPTIONS, (error, derivedKey) => {
      if (error) {
        reject(error);
        return;
      }

      resolve(derivedKey);
    });
  });
}

export async function hashPassword(password: string): Promise<string> {
  if (password.length < 12 || password.length > 256) {
    throw new Error('Password length must be between 12 and 256 characters.');
  }

  const salt = randomBytes(SCRYPT_SALT_BYTES);
  const derivedKey = await derivePasswordKey(password, salt);

  return [
    PASSWORD_FORMAT,
    PASSWORD_VERSION,
    String(SCRYPT_OPTIONS.N),
    String(SCRYPT_OPTIONS.r),
    String(SCRYPT_OPTIONS.p),
    salt.toString('base64url'),
    derivedKey.toString('base64url'),
  ].join('$');
}

export async function verifyPassword(password: string, encodedHash: string): Promise<boolean> {
  const parts = encodedHash.split('$');

  if (parts.length !== 7) {
    return false;
  }

  const [format, version, rawN, rawR, rawP, rawSalt, rawHash] = parts;

  if (
    !format ||
    !version ||
    !rawN ||
    !rawR ||
    !rawP ||
    !rawSalt ||
    !rawHash ||
    format !== PASSWORD_FORMAT ||
    version !== PASSWORD_VERSION
  ) {
    return false;
  }

  const N = Number(rawN);
  const r = Number(rawR);
  const p = Number(rawP);

  if (!Number.isSafeInteger(N) || !Number.isSafeInteger(r) || !Number.isSafeInteger(p)) {
    return false;
  }

  try {
    const salt = Buffer.from(rawSalt, 'base64url');
    const expected = Buffer.from(rawHash, 'base64url');

    const derived = await new Promise<Buffer>((resolve, reject) => {
      scrypt(
        password,
        salt,
        expected.length,
        {
          N,
          r,
          p,
          maxmem: 64 * 1024 * 1024,
        },
        (error, key) => {
          if (error) {
            reject(error);
            return;
          }

          resolve(key);
        },
      );
    });

    if (derived.length !== expected.length) {
      return false;
    }

    return timingSafeEqual(derived, expected);
  } catch {
    return false;
  }
}

export function createOpaqueToken(bytes = 48): string {
  if (!Number.isSafeInteger(bytes) || bytes < 32 || bytes > 128) {
    throw new Error('Opaque token length must be between 32 and 128 bytes.');
  }

  return randomBytes(bytes).toString('base64url');
}

export function hashOpaqueToken(token: string, pepper: string): string {
  if (pepper.length < 32) {
    throw new Error('Token pepper must contain at least 32 characters.');
  }

  return createHmac('sha256', pepper).update(token, 'utf8').digest('hex');
}
