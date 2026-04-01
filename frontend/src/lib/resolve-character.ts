import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc';

type ReadClient = Pick<SuiJsonRpcClient, 'getObject'>;

/**
 * Resolve a Character's Sui Object ID to its in-game item_id (u64).
 * Reads the on-chain Character object and extracts key.fields.item_id.
 */
export async function resolveCharacterItemId(client: ReadClient, characterObjectId: string): Promise<string> {
  const result = await client.getObject({
    id: characterObjectId,
    options: { showContent: true },
  });

  if (!result.data?.content || result.data.content.dataType !== 'moveObject') {
    throw new Error(`Character object not found: ${characterObjectId}`);
  }

  const fields = result.data.content.fields as Record<string, unknown>;
  const key = fields.key as { fields: { item_id: string } } | undefined;
  if (!key?.fields?.item_id) {
    throw new Error(`Character missing key.item_id: ${characterObjectId}`);
  }

  return key.fields.item_id;
}
