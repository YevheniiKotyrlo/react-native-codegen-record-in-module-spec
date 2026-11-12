import type {TurboModule} from 'react-native';
import {TurboModuleRegistry} from 'react-native';

export interface Spec extends TurboModule {
  setOptions(options: Record<string, unknown>): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('Sample');
