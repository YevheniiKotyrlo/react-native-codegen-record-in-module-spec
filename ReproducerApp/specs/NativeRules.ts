import type {TurboModule} from 'react-native';
import {TurboModuleRegistry} from 'react-native';

export interface Rule {
  readonly target: string;
  readonly matched: Record<string, unknown>;
}

export interface Spec extends TurboModule {
  configure(rules: ReadonlyArray<Rule>): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('Rules');
