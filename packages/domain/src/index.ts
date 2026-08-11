export type EntityId = string & { readonly __brand: 'EntityId' };

export function asEntityId(value: string): EntityId {
  if (value.trim().length === 0) {
    throw new Error('EntityId não pode ser vazio.');
  }

  return value as EntityId;
}
