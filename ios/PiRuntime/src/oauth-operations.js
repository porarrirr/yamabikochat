// Refresh and revocation share a queue so revocation always receives rotated tokens.
export class OAuthOperations {
  #pending = new Map();
  run(provider, operation) {
    const task = (this.#pending.get(provider) || Promise.resolve()).catch(() => {}).then(operation);
    this.#pending.set(provider, task);
    task.finally(() => { if (this.#pending.get(provider) === task) this.#pending.delete(provider); }).catch(() => {});
    return task;
  }
}
