import { z } from 'zod';

export const nonEmptyIdSchema = z.string().trim().min(1);
export const isoDateTimeSchema = z.iso.datetime();
