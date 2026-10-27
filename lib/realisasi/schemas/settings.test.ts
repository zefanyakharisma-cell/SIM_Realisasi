import { describe, expect, it } from 'vitest';
import { generalSettingsSchema } from '@/lib/realisasi/schemas/settings';

const valid = { grace_period_months: '6', reporting_deadline_days: '30', revision_reminder_days: '3', deadline_reminder_before_days: '7' };

describe('generalSettingsSchema', () => {
  it('coerces the form strings', () => {
    expect(generalSettingsSchema.parse(valid)).toEqual({
      grace_period_months: 6,
      reporting_deadline_days: 30,
      revision_reminder_days: 3,
      deadline_reminder_before_days: 7,
    });
  });

  it('rejects an emptied field instead of saving 0', () => {
    expect(generalSettingsSchema.safeParse({ ...valid, reporting_deadline_days: '' }).success).toBe(false);
    expect(generalSettingsSchema.safeParse({ ...valid, revision_reminder_days: '  ' }).success).toBe(false);
    expect(generalSettingsSchema.safeParse({ ...valid, deadline_reminder_before_days: '0' }).success).toBe(true);
  });

  it('caps the values like update_settings', () => {
    expect(generalSettingsSchema.safeParse({ ...valid, grace_period_months: '120' }).success).toBe(true);
    expect(generalSettingsSchema.safeParse({ ...valid, grace_period_months: '121' }).success).toBe(false);
    expect(generalSettingsSchema.safeParse({ ...valid, reporting_deadline_days: '3651' }).success).toBe(false);
  });
});
