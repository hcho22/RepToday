// Node unit-test base only. Workerd integration separately runs the actual platform class.
export class DurableObject {
  constructor(ctx, env) { this.ctx = ctx; this.env = env; }
}
