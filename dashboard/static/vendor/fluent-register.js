import {
  provideFluentDesignSystem,
  fluentBadge,
  fluentButton,
  fluentOption,
  fluentSelect,
} from "./fluent-web-components.min.js";

provideFluentDesignSystem().register(
  fluentBadge(),
  fluentButton(),
  fluentOption(),
  fluentSelect(),
);
