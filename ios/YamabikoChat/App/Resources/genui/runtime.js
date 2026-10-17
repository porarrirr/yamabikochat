/* Standalone GenUI renderer. No provider calls or remote executable dependencies. */
(function (global) {
    'use strict';
    const SVG_NS = 'http://www.w3.org/2000/svg';
    const referenceFactories = global.__GENUI_REFERENCE_COMPONENT_FACTORIES__ || {};
    const referenceComponents = new Map();
    const names = [
        'text',
        'title',
        'caption',
        'label',
        'badge',
        'bold',
        'italic',
        'underline',
        'strikethrough',
        'code',
        'math',
        'box',
        'row',
        'col',
        'grid',
        'grid-item',
        'flow',
        'flow-item',
        'card',
        'divider',
        'spacer',
        'blockquote',
        'button',
        'input',
        'textarea',
        'slider',
        'checkbox',
        'select',
        'segmented-control',
        'radio-group',
        'radio',
        'date-picker',
        'form',
        'pressable',
        'table',
        'table-section',
        'table-row',
        'table-cell',
        'list',
        'list-item',
        'carousel',
        'carousel-item',
        'carousel-media-item',
        'popover',
        'popover-trigger',
        'popover-content',
        'AsyncImage',
        'AsyncImageGroup',
        'AsyncVideo',
        'Chart',
        'MapWidgetV2',
        'icon',
        'favicon',
        'svg',
        'Link',
        'Entity',
        'Cite',
        'FileCite',
        'CodeCite',
        'FileNavList',
        'FollowUp',
        'MemoryCite',
        'AppBlock',
        'CodeBlock',
        'WritingBlock',
        'markdown',
        'text-only-markdown',
        'highlight',
        'loading',
        'loading-indicator',
        'loading-block',
        'pulse-indicator',
        'shimmer-text',
        'flashcard-flip',
        'animate',
        'animate-group',
        'animate-item',
        'transition',
        'celebration',
        'tooltip',
        'component',
        'component-content',
        'transparent',
        'CLIENT_DEFINED_WIDGET_TYPE',
        'DIL_RENDERED_PROP_ELEMENT_TYPE',
        'lottie',
        'youtube',
        'choice',
        'follow-up-action-bar',
        'horizontal-swipe-surface',
        'Each',
        'Scope',
        'Show',
        'Show.Else',
        'image',
        'search-image',
        'chart',
        'pie-chart',
        'audio-player',
        'run-interval',
        'link',
    ];
    names.push(...Object.keys(referenceFactories).filter((name) => !names.includes(name)));
    const aliases = {
        image: 'AsyncImage',
        'search-image': 'AsyncImage',
        chart: 'Chart',
        'pie-chart': 'Chart',
        link: 'Link',
        AudioPlayer: 'audio-player',
        RunInterval: 'run-interval',
        ListView: 'list',
        ListViewItem: 'list-item',
        ChartsWidgetV2: 'Chart',
        Animate: 'animate',
        'Animate.Item': 'animate-item',
        AnimateGroup: 'animate-group',
        Transition: 'transition',
        Response: 'col',
        Basic: 'box',
        Box: 'box',
        Row: 'row',
        Col: 'col',
        Inline: 'row',
        Grid: 'grid',
        'Grid.Item': 'grid-item',
        Flow: 'flow',
        'Flow.Item': 'flow-item',
        Card: 'card',
        Button: 'button',
        Badge: 'badge',
        Input: 'input',
        Textarea: 'textarea',
        Checkbox: 'checkbox',
        Slider: 'slider',
        Select: 'select',
        DatePicker: 'date-picker',
        SegmentedControl: 'segmented-control',
        RadioGroup: 'radio-group',
        List: 'list',
        'List.Item': 'list-item',
        Item: 'list-item',
        Table: 'table',
        'Table.Row': 'table-row',
        'Table.Cell': 'table-cell',
        'Table.Section': 'table-section',
        Carousel: 'carousel',
        'Carousel.Item': 'carousel-item',
        'Carousel.MediaItem': 'carousel-media-item',
        BaseCarousel: 'carousel',
        'BaseCarousel.Item': 'carousel-item',
        'BaseCarousel.MediaItem': 'carousel-media-item',
        CardCarousel: 'carousel',
        Popover: 'popover',
        'Popover.Trigger': 'popover-trigger',
        'Popover.Content': 'popover-content',
        Pressable: 'pressable',
        Form: 'form',
        Spacer: 'spacer',
        Divider: 'divider',
        Icon: 'icon',
        Image: 'AsyncImage',
        Favicon: 'favicon',
        SearchImage: 'search-image',
        HorizontalSwipeSurface: 'horizontal-swipe-surface',
        FollowUpActionBar: 'follow-up-action-bar',
        LoadingDot: 'pulse-indicator',
        LoadingBlock: 'loading-block',
        LoadingIndicator: 'loading-indicator',
        PulseIndicator: 'pulse-indicator',
        Celebration: 'celebration',
        PieChart: 'pie-chart',
        DILMap: 'MapWidgetV2',
        YouTubeEmbed: 'youtube',
        OverflowRow: 'horizontal-swipe-surface',
    };
    names.push(...Object.keys(aliases).filter((name) => !names.includes(name)));
    const canonicalType = (name) => aliases[aliases[name] || name] || aliases[name] || name;
    const clone = (value) => JSON.parse(JSON.stringify(value === undefined ? {} : value));
    const safeURL = (value) => {
        try {
            const u = new URL(String(value));
            return u.protocol === 'https:' && !u.username && !u.password ? u.href : null;
        } catch (_) {
            return null;
        }
    };
    const size = (value, spacing = false) =>
        typeof value === 'number'
            ? `${value * (spacing ? 4 : 1)}px`
            : {
                  xs: '10px',
                  sm: '12px',
                  md: '16px',
                  lg: '20px',
                  xl: '24px',
                  '2xl': '32px',
                  full: '100%',
              }[value] || value;
    const compactSpacing = (value) => size(value, true);
    const readPath = (object, path) =>
        String(path)
            .split('.')
            .reduce(
                (value, key) =>
                    ['__proto__', 'prototype', 'constructor'].includes(key)
                        ? undefined
                        : value?.[key],
                object,
            );
    const interpolate = (value, state) =>
        typeof value === 'string'
            ? value.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, key) =>
                  String(readPath(state, key) ?? ''),
              )
            : value;
    const resolve = (value, state) =>
        typeof value === 'string'
            ? /^\{\{\s*[^}]+?\s*\}\}$/.test(value)
                ? (readPath(state, value.slice(2, -2).trim()) ?? '')
                : interpolate(value, state)
            : Array.isArray(value)
              ? value.map((v) => resolve(v, state))
              : value && typeof value === 'object'
                ? Object.fromEntries(Object.entries(value).map(([k, v]) => [k, resolve(v, state)]))
                : value;
    const evaluateCEL = (expression, bindings) => {
        const response = global.__GENUI_EVALUATE_CEL__
            ? global.__GENUI_EVALUATE_CEL__(expression, bindings)
            : JSON.parse(
                  global.prompt('__genuiCEL:' + JSON.stringify({ expression, bindings })) ||
                      '{"error":"Original CEL host is unavailable"}',
              );
        if (response.error) throw Error(response.error);
        return response.value;
    };
    const h = (type, props, ...children) => ({
        type,
        props: props || {},
        children: children.flat(Infinity),
    });
    // Apply a complete patch batch atomically. Model strings are treated only as data.
    function applyJSONPatch(documentValue, operations) {
        const result = clone(documentValue);
        let root = result;
        if (!Array.isArray(operations)) throw Error('Patch must be an array');
        for (const operation of operations) {
            if (!['add', 'replace', 'remove', 'append'].includes(operation.op))
                throw Error(`Unsupported patch operation: ${operation.op}`);
            if (
                typeof operation.path !== 'string' ||
                (operation.path !== '' && !operation.path.startsWith('/'))
            )
                throw Error('Invalid JSON pointer');
            const keys =
                operation.path === ''
                    ? []
                    : operation.path
                          .slice(1)
                          .split('/')
                          .map((key) => {
                              if (/~(?![01])/u.test(key))
                                  throw Error('Invalid JSON pointer escape');
                              const decoded = key.replace(/~1/g, '/').replace(/~0/g, '~');
                              if (['__proto__', 'prototype', 'constructor'].includes(decoded))
                                  throw Error('Unsafe patch key');
                              return decoded;
                          });
            if (operation.op !== 'remove' && !Object.hasOwn(operation, 'value'))
                throw Error('Patch requires value');
            if (!keys.length) {
                if (operation.op === 'remove') throw Error('Cannot remove document root');
                if (operation.op === 'append') root = appendValue(root, operation.value);
                else root = clone(operation.value);
                continue;
            }
            let parent = root;
            for (const key of keys.slice(0, -1)) {
                if (!parent || typeof parent !== 'object' || !Object.hasOwn(parent, key))
                    throw Error('Patch path not found');
                parent = parent[key];
            }
            if (!parent || typeof parent !== 'object')
                throw Error('Patch parent must be an object');
            const key = keys.at(-1),
                exists = Object.hasOwn(parent, key);
            if (operation.op !== 'add' && !exists) throw Error('Patch target not found');
            if (Array.isArray(parent)) {
                if (!(key === '-' && operation.op === 'add') && !/^(0|[1-9][0-9]*)$/.test(key))
                    throw Error('Invalid array index');
                const index = key === '-' ? parent.length : Number(key);
                if (index > parent.length || (operation.op !== 'add' && index === parent.length))
                    throw Error('Array index out of bounds');
                if (operation.op === 'add') parent.splice(index, 0, clone(operation.value));
                else if (operation.op === 'remove') parent.splice(index, 1);
                else
                    parent[index] =
                        operation.op === 'append'
                            ? appendValue(parent[index], operation.value)
                            : clone(operation.value);
            } else {
                if (operation.op === 'remove') delete parent[key];
                else
                    parent[key] =
                        operation.op === 'append'
                            ? appendValue(parent[key], operation.value)
                            : clone(operation.value);
            }
        }
        return root;
    }
    function appendValue(target, value) {
        if (typeof target === 'string' && typeof value === 'string') return target + value;
        if (Array.isArray(target)) return target.concat(clone(value));
        throw Error('Append requires an array or string');
    }

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = {
            safeURL,
            size,
            compactSpacing,
            interpolate,
            resolve,
            h,
            componentNames: names,
            applyJSONPatch,
        };
    }
    if (!global.document) return;
    const document = global.document,
        config = global.__GENUI_DOCUMENT__ || {};
    const saved = global.__GENUI_SAVED_STATE__ || {};
    let state = { ...clone(config.state), ...clone(saved.bindings) },
        trusted = false,
        scheduled = false,
        current = null,
        hookIndex = 0;
    const hooks = new Map(),
        effects = [],
        maps = [],
        videos = [],
        usedHooks = new Set();
    const chartWidths = new Map(),
        flashcardMotions = new Map();
    let stateSlotIndex = 0;
    const stateSlots = [];
    const getSnapshot = () => ({
        bindings: clone(state),
        hooks: stateSlots.map((s) => {
            try {
                return clone(s.value);
            } catch (_) {
                return null;
            }
        }),
        hookSlots: Object.fromEntries(
            Array.from(hooks).flatMap(([path, list]) =>
                list.flatMap((s, index) =>
                    s.kind === 'state' && s.value !== undefined
                        ? [[`${path}:${index}`, clone(s.value)]]
                        : [],
                ),
            ),
        ),
    });
    const bridge = (payload) => global.webkit?.messageHandlers?.genui?.postMessage(payload);
    const guarded = (type, args) => {
        if (trusted) bridge({ type, ...args });
    };
    const GenUI = Object.freeze({
        copy: (text) => guarded('copy', { text: String(text) }),
        openUrl: (url) => {
            const valid = safeURL(url);
            if (valid) guarded('openUrl', { url: valid });
        },
        issueNewTurn: (query) => guarded('issueNewTurn', { query: String(query) }),
        openEntityDetail: (args) => guarded('openEntityDetail', { args }),
        logEvent: (event) => bridge({ type: 'referenceEvent', event }),
        dispatchAction: (request) => dispatchReferenceAction(request),
        dispatchWidgetAction: (request) => dispatchReferenceAction(request),
        openImageLightbox: (request, index = 0) =>
            guarded('openImageLightbox', {
                args: Array.isArray(request)
                    ? {
                          images: request.map((image) =>
                              typeof image === 'string' ? { image_url: image } : image,
                          ),
                          selected_index: index,
                      }
                    : request,
            }),
        refresh: () => unavailableReference('refresh'),
        refreshWidget: () => unavailableReference('refreshWidget'),
    });
    function unavailableReference(type) {
        const reason = `reference-server-required:${type}`;
        bridge({ type: 'unsupported', reason });
        return Promise.resolve({ status: 'unsupported', reason });
    }
    function dispatchReferenceAction(request) {
        // Only app-owned client actions are executable here. Original remote actions
        // retain their identity and expose an explicit unavailable result.
        if (request.handler === 'server' || request.nativeWidgetResolutionId) {
            return unavailableReference(request.type);
        }
        const payload = request.payload || {};
        if (['open_url', 'openUrl'].includes(request.type)) GenUI.openUrl(payload.url);
        else if (['copy', 'copy_text'].includes(request.type)) GenUI.copy(payload.text);
        else if (['issue_new_turn', 'issueNewTurn'].includes(request.type))
            GenUI.issueNewTurn(payload.query || payload.text);
        else if (request.type === 'prefill_composer' || request.type === 'chat.fill')
            guarded('prefillComposer', { text: String(payload.prompt || payload.text || payload.query || '') });
        else if (request.type === 'email.mailto') guarded('composeEmail', { args: payload });
        else if (request.type === 'card.share') guarded('share', { args: payload });
        else if (request.type === 'link.open') GenUI.openUrl(payload.url || payload.href);
        else if (request.type === 'open_entity_detail') GenUI.openEntityDetail(payload);
        else if (request.type === 'open_image_lightbox') GenUI.openImageLightbox(payload);
        else if (request.type === 'log_event') GenUI.logEvent(payload);
        else if (request.type === 'share') guarded('share', { args: payload });
        else if (request.type === 'open_video_lightbox')
            guarded('openVideoLightbox', { args: payload });
        else {
            bridge({
                type: 'unsupported',
                reason: `reference-client-action:${request.type}`,
            });
            return Promise.resolve({
                status: 'unsupported',
                reason: `reference-client-action:${request.type}`,
            });
        }
        return Promise.resolve({ status: 'complete' });
    }
    const referenceJSX = { jsx: h, jsxs: h, Fragment: (_props) => _props.children };
    function referenceBoundary({ Component, componentProps }) {
        return h(Component, componentProps);
    }
    function referenceComponent(name) {
        if (!referenceComponents.has(name))
            referenceComponents.set(
                name,
                referenceFactories[name](DIL, GenUI, referenceJSX, referenceBoundary),
            );
        return referenceComponents.get(name);
    }
    const depsEqual = (a, b) =>
        Array.isArray(a) &&
        Array.isArray(b) &&
        a.length === b.length &&
        a.every((v, i) => Object.is(v, b[i]));
    function slot(init) {
        if (!current) throw Error('Hooks must be called while rendering a component');
        usedHooks.add(current);
        const list = hooks.get(current) || [];
        hooks.set(current, list);
        const i = hookIndex++;
        if (!list[i]) list[i] = init();
        return list[i];
    }
    const DIL = {
        h,
        createElement: h,
        render(value) {
            codeOutput = value;
            return value;
        },
        useConstants(selector) {
            const value = config.state?.constants || {};
            return selector ? selector(value) : value;
        },
        useState(initial) {
            const index = stateSlotIndex++,
                identity = `${current}:${hookIndex}`;
            const s = slot(() => ({
                kind: 'state',
                value:
                    saved.hookSlots && Object.hasOwn(saved.hookSlots, identity)
                        ? saved.hookSlots[identity]
                        : !saved.hookSlots &&
                            Array.isArray(saved.hooks) &&
                            index < saved.hooks.length
                          ? saved.hooks[index]
                          : typeof initial === 'function'
                            ? initial()
                            : initial,
            }));
            stateSlots[index] = s;
            return [
                s.value,
                (v) => {
                    const next = typeof v === 'function' ? v(s.value) : v;
                    if (!Object.is(s.value, next)) {
                        s.value = next;
                        queueRender();
                    }
                },
            ];
        },
        useMemo(fn, deps) {
            const s = slot(() => ({}));
            if (!('value' in s) || !depsEqual(s.deps, deps)) {
                s.value = fn();
                s.deps = deps;
            }
            return s.value;
        },
        useCallback(fn, deps) {
            return DIL.useMemo(() => fn, deps);
        },
        useRef(value) {
            return slot(() => ({ current: value }));
        },
        useId() {
            return slot(() => ({ id: `genui-${current.replace(/[^a-z0-9]/gi, '-')}-${hookIndex}` }))
                .id;
        },
        useEffect(fn, deps) {
            const s = slot(() => ({}));
            if (!depsEqual(s.deps, deps)) {
                s.deps = deps;
                effects.push(() => {
                    s.cleanup?.();
                    s.cleanup = fn();
                });
            }
        },
        useTheme() {
            const theme = renderTheme || global.__GENUI_THEME__ || 'light';
            return { theme, isDark: theme === 'dark', isLight: theme === 'light' };
        },
        useAppData(selector) {
            const supplied = config.state?.appData || { opGenui: config.state?.opGenui };
            const data = { ...supplied, opGenui: { ...supplied.opGenui,
                supportedClientActions: ['copy', 'open_url', 'issue_new_turn', 'open_entity_detail',
                    'open_image_lightbox', 'open_video_lightbox', 'share', 'log_event', 'prefill_composer', 'email.mailto'] } };
            return typeof selector === 'function' ? selector(data) : data;
        },
        useIsMobile() {
            return global.__GENUI_IS_MOBILE__ ?? true;
        },
        useBreakpoint(query) {
            const thresholds = { xs: 380, sm: 576, md: 768, lg: 1024, xl: 1280, '2xl': 1536 };
            if (query) return global.innerWidth >= thresholds[query];
            return Object.keys(thresholds).filter((key) => global.innerWidth >= thresholds[key]);
        },
        useSpeechSynthesizer(source) {
            const [status, setStatus] = DIL.useState('idle'),
                [error, setError] = DIL.useState(null);
            const utterance = DIL.useRef(null);
            const stop = DIL.useCallback(() => {
                global.speechSynthesis?.cancel();
                setStatus('idle');
            }, []);
            DIL.useEffect(() => stop, [stop]);
            return {
                available: !!global.speechSynthesis,
                status,
                error,
                stop,
                play: () => {
                    if (!trusted || !global.speechSynthesis) return;
                    const text = source.text || source.value || source.utterance || '';
                    if (!text) { setError('Supplied speech text is required'); return; }
                    const item = new global.SpeechSynthesisUtterance(text);
                    item.rate = Math.max(0.1, Math.min(10, Number(source.playbackSpeed) || 1));
                    utterance.current = item;
                    if (source.language || source.lang) item.lang = source.language || source.lang;
                    item.onend = () => setStatus('idle');
                    item.onerror = (event) => {
                        setError(event.error);
                        setStatus('idle');
                    };
                    setError(null);
                    setStatus('playing');
                    global.speechSynthesis.speak(item);
                },
            };
        },
        useNow(active = true, interval = 1000) {
            const [now, setNow] = DIL.useState(() => Date.now());
            DIL.useEffect(() => {
                if (!active) return;
                const timer = global.setInterval(() => setNow(Date.now()), interval);
                return () => global.clearInterval(timer);
            }, [active, interval]);
            return now;
        },
    };
    names.forEach((name) => {
        DIL[name] = name;
    });
    global.__dil = referenceJSX;
    for (const name of Object.keys(referenceFactories)) {
        Object.defineProperty(global, name, {
            configurable: true,
            get: () => referenceComponent(name),
        });
    }
    global.DIL = DIL;
    global.GenUI = GenUI;
    let draggingInput = null;
    document.addEventListener?.(
        'pointerdown',
        (event) => {
            if (event.target?.tagName === 'INPUT' && event.target.type === 'range')
                draggingInput = event.target;
        },
        true,
    );
    document.addEventListener?.('pointerdown', (event) => {
        document.querySelectorAll?.('.genui-popover[open]').forEach((popover) => {
            if (!popover.contains(event.target)) popover.open = false;
        });
    });
    document.addEventListener?.('keydown', (event) => {
        if (event.key === 'Escape')
            document
                .querySelectorAll?.('.genui-popover[open]')
                .forEach((popover) => (popover.open = false));
    });
    const endDrag = () => {
        if (draggingInput) {
            draggingInput = null;
            queueRender();
        }
    };
    document.addEventListener?.('pointerup', endDrag, true);
    document.addEventListener?.('pointercancel', endDrag, true);
    let codeRender, codeOutput;
    try {
        if (config.code)
            codeRender = new Function('DIL', 'GenUI', 'state', 'resources', config.code);
    } catch (e) {
        bridge({ type: 'error', message: String(e.message) });
        config.ui = h('text', { color: 'danger' }, `JavaScript error: ${e.message}`);
    }
    // Listener ownership and keyed DOM reconciliation preserve real input identity.
    // Callback closures refer to the newly authored node; forward those references
    // to the live node after reconciliation, rather than to a detached element.
    function listen(element, type, handler) {
        (element.__genuiListeners ||= []).push([type, handler]);
        element.addEventListener(type, handler);
    }
    const liveElements = new WeakMap(), swipeStates = new WeakMap();
    const liveElement = (element) => liveElements.get(element) || element;
    const pendingMath = new Set();
    let typesettingMath = false;
    function markMath(element, source) {
        element.__mathSource = source;
        effects.push(() => {
            const target = liveElement(element);
            if (target.__typesetSource !== source) pendingMath.add(target);
        });
    }
    function typesetPendingMath() {
        const math = global.MathJax;
        if (typesettingMath || !pendingMath.size) return;
        const targets = Array.from(pendingMath).filter(element => element.isConnected && element.__mathSource != null);
        pendingMath.clear();
        if (!targets.length) return;
        for (const target of targets) {
            if (target.__mathTemplate) {
                math?.typesetClear?.([target]);
                for (const child of Array.from(target.childNodes)) disposeElement(child);
                target.replaceChildren(...Array.from(target.__mathTemplate.childNodes));
                delete target.__mathTemplate;
            }
        }
        if (!math?.typesetPromise) return;
        typesettingMath = true;
        const sources = targets.map(element => element.__mathSource);
        targets.forEach((element, index) => { element.__typesetSource = sources[index]; });
        Promise.resolve().then(() => math.typesetPromise(targets)).then(reportLayout).catch(error => {
            targets.forEach((element, index) => {
                if (element.__typesetSource === sources[index]) delete element.__typesetSource;
            });
            bridge({type:'warning', path:'math', message:String(error.message || error)});
        }).finally(() => {
            typesettingMath = false;
            typesetPendingMath();
        });
    }
    function forwardReference(authored, live) {
        for (const key of [
            'value',
            'checked',
            'open',
            'scrollLeft',
            'scrollTop',
            'disabled',
            'required',
            'currentTime',
            'playbackRate',
            'volume',
            '__animation',
            '__motion',
            'textContent',
            'style',
            'children',
            'firstElementChild',
            'parentElement',
            'offsetLeft',
            'clientWidth',
            'clientHeight',
            'scrollHeight',
        ]) {
            if (key in authored)
                Object.defineProperty(authored, key, {
                    configurable: true,
                    get: () => live[key],
                    set: (value) => {
                        live[key] = value;
                    },
                });
        }
        for (const method of [
            'focus',
            'play',
            'pause',
            'select',
            'setSelectionRange',
            'closest',
            'scrollBy',
            'replaceWith',
            'getBoundingClientRect',
            'querySelector',
            'querySelectorAll',
        ]) {
            if (typeof live[method] === 'function') authored[method] = live[method].bind(live);
        }
    }
    function reconcileElement(live, authored) {
        if (
            live.nodeType !== authored.nodeType ||
            live.nodeName !== authored.nodeName ||
            live.namespaceURI !== authored.namespaceURI
        )
            return authored;
        if (live.nodeType === 3) {
            if (live.nodeValue !== authored.nodeValue) live.nodeValue = authored.nodeValue;
            return live;
        }
        if (live.nodeType !== 1) return authored;
        liveElements.set(authored, live);
        for (const attr of Array.from(live.attributes))
            if (!authored.hasAttribute(attr.name)) live.removeAttribute(attr.name);
        for (const attr of Array.from(authored.attributes))
            if (live.getAttribute(attr.name) !== attr.value)
                live.setAttribute(attr.name, attr.value);
        // Selection and an in-progress native drag survive property updates.
        const selection =
            live === document.activeElement && 'selectionStart' in live
                ? [live.selectionStart, live.selectionEnd]
                : null;
        const nextValue = authored.value;
        if (live.__motionKey !== authored.__motionKey) {
            live.__motion?.cancel?.();
            live.__motion = null;
        }
        live.__motionKey = authored.__motionKey;
        if (live.__animation && live.__animationKey === authored.__animationKey) {
            authored.__animation = live.__animation;
        } else {
            live.__animation?.destroy();
            live.__animation = null;
            const sameMath = authored.__mathSource != null && live.__mathSource === authored.__mathSource;
            if (authored.__mathSource != null && !sameMath) {
                // Wait for any active typeset before replacing its input. Keep
                // the authored children untouched so their listeners stay valid.
                live.__mathTemplate = authored;
                delete live.__typesetSource;
            } else if (!sameMath) {
                if (live.__mathSource != null) global.MathJax?.typesetClear?.([live]);
                delete live.__mathTemplate;
                delete live.__typesetSource;
                reconcileChildren(live, authored);
            }
        }
        live.__mathSource = authored.__mathSource;
        live.__animationKey = authored.__animationKey;
        for (const key of ['checked', 'disabled', 'required', 'open'])
            if (key in authored && live[key] !== authored[key]) live[key] = authored[key];
        if ('value' in authored && live.value !== nextValue) {
            // A numeric control may retain an equivalent draft such as "01" while focused.
            const equivalent =
                live === document.activeElement &&
                live.type === 'number' &&
                nextValue !== '' &&
                Number(live.value) === Number(nextValue);
            if (!equivalent) live.value = nextValue;
        }
        if (selection)
            try {
                live.setSelectionRange(...selection);
            } catch (_) {}
        for (const [type, handler] of live.__genuiListeners || [])
            live.removeEventListener(type, handler);
        live.__genuiListeners = [];
        for (const [type, handler] of authored.__genuiListeners || []) listen(live, type, handler);
        live.__genuiBindingProps = authored.__genuiBindingProps;
        forwardReference(authored, live);
        return live;
    }
    function disposeElement(element) {
        pendingMath.delete(element);
        if (element.__mathSource != null) global.MathJax?.typesetClear?.([element]);
        swipeStates.delete(element);
        element.__animation?.destroy();
        element.__motion?.cancel?.();
        const motion = flashcardMotions.get(element.dataset?.nodePath);
        if (motion) { clearTimeout(motion.timer); flashcardMotions.delete(element.dataset.nodePath); }
        for (const child of Array.from(element.childNodes || [])) disposeElement(child);
    }
    function reconcileChildren(parent, authored) {
        const previous = Array.from(parent.childNodes),
            next = Array.from(authored.childNodes);
        const keyed = new Map(
            previous
                .filter((item) => item.dataset?.nodePath)
                .map((item) => [item.dataset.nodePath, item]),
        );
        const retained = new Set();
        next.forEach((child, index) => {
            const key = child.dataset?.nodePath;
            const old = key
                ? keyed.get(key)
                : previous[index]?.dataset?.nodePath
                  ? null
                  : previous[index];
            const live = old && !retained.has(old) ? reconcileElement(old, child) : child;
            retained.add(live);
            if (parent.childNodes[index] !== live)
                parent.insertBefore(live, parent.childNodes[index] || null);
        });
        for (const child of Array.from(parent.childNodes)) if (!retained.has(child)) {
            disposeElement(child);
            child.remove();
        }
    }

    function queueRender() {
        if (!scheduled) {
            scheduled = true;
            queueMicrotask(() => {
                const update = () => {
                    scheduled = false;
                    render();
                };
                // Native range inputs can emit several events per display frame.
                // Keep the thumb responsive and reconcile the latest state once.
                if (draggingInput) requestAnimationFrame(update);
                else update();
            });
        }
    }
    function action(handler, value, event) {
        const old = trusted;
        trusted = event?.isTrusted === true;
        try {
            if (typeof handler === 'function') handler(value, event);
            else if (handler && typeof handler === 'object') {
                const resolved = resolve(handler, renderScope);
                handler = resolved;
                if (handler.handler) return dispatchReferenceAction(handler);
                const v = handler.value === '$value' ? value : handler.value;
                switch (handler.type) {
                    case 'setState':
                        if (['__proto__', 'prototype', 'constructor'].includes(handler.key))
                            throw Error('Invalid state key');
                        if (!Object.is(state[handler.key], v)) {
                            state[handler.key] = v;
                            queueRender();
                        }
                        break;
                    case 'resetState':
                        global.GenUIRuntime.reset();
                        break;
                    case 'copy':
                        GenUI.copy(handler.text ?? value);
                        break;
                    case 'openUrl':
                        GenUI.openUrl(handler.url);
                        break;
                    case 'issueNewTurn':
                        GenUI.issueNewTurn(handler.query);
                        break;
                    case 'openEntityDetail':
                        GenUI.openEntityDetail(handler.args);
                        break;
                    case 'openMap':
                        guarded('openMap', { props: clone(handler.props) });
                        break;
                }
            }
        } finally {
            trusted = old;
        }
    }
    function bind(el, p, event = 'change', read = () => el.value) {
        el.__genuiBindingProps = p;
        listen(el, event, (e) => {
            const props = el.__genuiBindingProps;
            const v = read();
            if (
                props.bind &&
                !['__proto__', 'prototype', 'constructor'].includes(props.bind) &&
                !Object.is(state[props.bind], v)
            ) {
                state[props.bind] = v;
                queueRender();
            }
            action(props.onChange, v, e);
        });
    }
    function resource(ref) {
        return config.resources?.[ref] || null;
    }
    function missing(el, message) {
        el.classList.add('genui-unavailable');
        el.textContent = message;
        return el;
    }
    const referenceTokens = global.__GENUI_REFERENCE_TOKENS__ || {};
    const paletteKeys = new Set(Object.keys(referenceTokens.DIL_LIGHT_COLOR_PALETTE || {}));
    const tokenStyle = document.createElement('style');
    const paletteCSS = (palette) =>
        Object.entries(palette || {})
            .map(([key, value]) => `--dil-${key}:${value}`)
            .join(';');
    tokenStyle.textContent = `:root,[data-theme="light"]{${paletteCSS(referenceTokens.DIL_LIGHT_COLOR_PALETTE)}}[data-theme="dark"]{${paletteCSS(referenceTokens.DIL_DARK_COLOR_PALETTE)}}`;
    document.head?.append(tokenStyle);
    const themed = (value) =>
        value && typeof value === 'object' && ('light' in value || 'dark' in value)
            ? value[renderTheme || global.__GENUI_THEME__ || 'light']
            : value;
    const color = (value) => {
        value = themed(value);
        if (['info', 'success', 'warning', 'danger', 'discovery', 'default'].includes(value))
            value = value === 'default' ? 'color-border' : `color-text-${value}`;
        return paletteKeys.has(value) ? `var(--dil-${value})` : value;
    };
    const radius = (value) =>
        typeof value === 'number'
            ? size(value)
            : size(
                  {
                      none: 0,
                      '2xs': 2,
                      xs: 4,
                      sm: 6,
                      md: 8,
                      lg: 10,
                      xl: 12,
                      '2xl': 16,
                      '3xl': 20,
                      '4xl': 24,
                      full: 999,
                      pill: 999,
                  }[value] ?? value,
              );
    function spacing(s, key, value) {
        if (!value || typeof value !== 'object') {
            s[key] = size(value, true);
            return;
        }
        for (const side of ['Top', 'Right', 'Bottom', 'Left']) {
            const axis = ['Top', 'Bottom'].includes(side) ? 'y' : 'x';
            const item = value[side.toLowerCase()] ?? value[axis];
            if (item != null) s[key + side] = size(item, true);
        }
    }
    function style(el, p, type) {
        const s = el.style;
        const colors = {
            primary: 'var(--text)',
            secondary: 'var(--muted)',
            tertiary: 'var(--tertiary)',
            surface: 'var(--surface)',
            'surface-secondary': 'var(--soft)',
            'surface-soft': 'var(--surface-soft)',
            'surface-elevated': 'var(--surface-elevated)',
            border: 'var(--border)',
            discovery: 'var(--discovery)',
            success: 'var(--success)',
            danger: 'var(--danger)',
            warning: 'var(--warning)',
            info: 'var(--info)',
        };
        for (const key of ['width', 'height', 'minWidth', 'maxWidth', 'minHeight', 'maxHeight'])
            if (p[key] != null) s[key] = size(p[key]);
        const compact = global.innerWidth < 640;
        for (const key of ['gap', 'padding', 'columnGap', 'rowGap'])
            if (p[key] != null) spacing(s, key, p[key]);
        if (p.size && ['box', 'row', 'col', 'pressable', 'flow-item'].includes(type)) {
            s.width = size(p.size);
            s.height = size(p.size);
        }
        if (p.minSize) {
            s.minWidth = size(p.minSize);
            s.minHeight = size(p.minSize);
        }
        if (p.maxSize) {
            s.maxWidth = size(p.maxSize);
            s.maxHeight = size(p.maxSize);
        }
        if (p.color) s.color = color(p.color) || colors[p.color];
        if (p.background) s.background = color(p.background) || colors[p.background];
        if (p.radius != null) s.borderRadius = radius(p.radius);
        if (p.border) {
            const border =
                typeof p.border === 'object'
                    ? p.border
                    : {
                          width: typeof p.border === 'number' ? p.border : 1,
                          color: typeof p.border === 'string' ? p.border : 'alpha-10',
                      };
            s.border = `${border.width ?? border.size ?? 1}px ${border.style || 'solid'} ${color(border.color || 'alpha-10')}`;
        }
        if (p.align) s.alignItems = { start: 'flex-start', end: 'flex-end' }[p.align] || p.align;
        if (p.justify)
            s.justifyContent =
                {
                    start: 'flex-start',
                    end: 'flex-end',
                    between: 'space-between',
                    around: 'space-around',
                    evenly: 'space-evenly',
                }[p.justify] || p.justify;
        if (p.direction)
            s.flexDirection =
                p.direction === 'horizontal'
                    ? 'row'
                    : p.direction === 'vertical'
                      ? 'column'
                      : p.direction;
        if (type === 'radio-group' && p.direction === 'vertical') s.flexDirection = 'column';
        if (p.wrap != null)
            s.flexWrap = typeof p.wrap === 'string' ? p.wrap : p.wrap ? 'wrap' : 'nowrap';
        if (p.flex != null) {
            if (typeof p.flex === 'object') {
                s.flexGrow = String(p.flex.grow ?? 0);
                s.flexShrink = String(p.flex.shrink ?? 1);
                if (p.flex.basis != null) s.flexBasis = size(p.flex.basis);
            } else s.flex = String(p.flex);
        }
        if (p.clip) s.overflow = 'hidden';
        if (p.scrollable) s.overflow = 'auto';
        if (p.aspectRatio) s.aspectRatio = String(p.aspectRatio);
        if (p.flush) s.margin = '0';
        if (p.disableAutoSpacing && p.gap == null) s.gap = '0';
        if (p.weight || p.strong)
            s.fontWeight =
                { regular: 400, medium: 500, semibold: 600, bold: 700 }[p.weight] ||
                p.weight ||
                (p.strong ? 600 : 400);
        if (p.italic) s.fontStyle = 'italic';
        if (p.underline) s.textDecoration = 'underline';
        if (p.lineThrough) s.textDecoration = 'line-through';
        if (p.textAlign) s.textAlign = p.textAlign;
        if (p.tabularNums) s.fontVariantNumeric = 'tabular-nums';
        if (p.highlight) s.background = 'var(--highlight)';
        // Plain labels/prose retain authored line breaks, including recovered templates.
        // Markdown and SVG keep their own whitespace rules. Explicit literal mode also
        // preserves spaces; false opts back into ordinary HTML whitespace collapsing.
        if (['text', 'title', 'caption', 'label'].includes(type) && el.className !== 'genui-markdown')
            s.whiteSpace = p.preserveWhitespace === false ? 'normal' : 'pre-line';
        if (p.preserveWhitespace) s.whiteSpace = 'pre-wrap';
        if (p.inline) s.display = 'inline-flex';
        if (p.block) {
            s.display = 'block';
            s.width = '100%';
        }
        if (p.pill) s.borderRadius = '999px';
        if (p.maxLines) {
            s.display = '-webkit-box';
            s.webkitBoxOrient = 'vertical';
            s.webkitLineClamp = String(p.maxLines);
            s.overflow = 'hidden';
        } else if (p.truncate) {
            s.whiteSpace = 'nowrap';
            s.overflow = 'hidden';
            s.textOverflow = 'ellipsis';
        }
        if (p.minLines) s.minHeight = `${p.minLines * 1.5}em`;
        if (
            ['text', 'title', 'caption', 'label', 'markdown', 'text-only-markdown'].includes(type)
        ) {
            const family = ['title', 'caption'].includes(type) ? type : 'text';
            const table = referenceTokens.typography?.[family];
            const metric = table?.[p.size || 'md'] || table?.md;
            if (metric) {
                s.fontSize = size(typeof p.size === 'number' ? p.size : metric.fontSize);
                s.lineHeight = size(metric.lineHeight);
            }
        }
        if (['button', 'input', 'textarea', 'select', 'segmented-control'].includes(type)) {
            const defaultSize =
                type === 'button'
                    ? 'lg'
                    : ['input', 'textarea', 'select'].includes(type)
                      ? 'xl'
                      : 'md';
            const controlSize = p.size || defaultSize;
            const metrics =
                referenceTokens.controlMetrics?.[controlSize] ||
                referenceTokens.controlMetrics?.[defaultSize];
            if (metrics) {
                s.fontSize = size(metrics.fontSize);
                s.minHeight = size(metrics.height);
                if (type !== 'textarea') s.height = size(metrics.height);
                const radiusValue = metrics.textInput.borderRadius;
                s.borderRadius = radius(p.radius ?? radiusValue);
                s.padding = `0 ${metrics.textInput.gutter}px`;
            }
            if (type === 'button') {
                const gutters = {
                    '3xs': 6,
                    '2xs': 8,
                    xs: 8,
                    sm: 10,
                    md: 12,
                    lg: 12,
                    xl: 14,
                    '2xl': 14,
                    '3xl': 16,
                };
                s.padding = `0 ${gutters[controlSize] || 12}px`;
                s.gap = ['3xs', '2xs', 'xs', 'sm'].includes(p.size) ? '4px' : '6px';
                const variant =
                    { primary: 'solid', link: 'ghost' }[p.variant] || p.variant || 'solid';
                const tone =
                    typeof p.color === 'string' &&
                    [
                        'primary',
                        'secondary',
                        'info',
                        'success',
                        'warning',
                        'danger',
                        'discovery',
                    ].includes(p.color)
                        ? p.color
                        : 'primary';
                s.background = color(`color-background-${tone}-${variant}`);
                s.color = color(`color-text-${tone}-${variant}`);
                s.borderColor = color(`color-border-${tone}-${variant}`) || 'transparent';
                if (p.uniform) {
                    s.width = size(metrics.height);
                    s.padding = '0';
                }
            }
        }
        if (['input', 'textarea'].includes(type) && p.variant === 'plain') {
            s.background = 'transparent';
            s.border = '0';
            s.padding = '0';
            s.lineHeight = '1.33';
        }
        if (type === 'card') {
            const soft = p.variant === 'soft';
            s.background = color(p.background || (soft ? 'surface-tertiary' : 'surface-elevated'));
            s.border = soft ? '0' : `1px solid ${color('color-border')}`;
            s.borderRadius = radius(p.radius ?? (soft ? 12 : 20));
            spacing(s, 'padding', p.padding ?? (soft ? 3 : 4));
            const widths = {
                sm: 360,
                md: 440,
                lg: 560,
                small: 360,
                medium: 440,
                large: 560,
                full: '100%',
            };
            if (p.size) {
                s.width = size(widths[p.size] ?? p.size);
                s.maxWidth = '100%';
            }
        }
        if (type === 'icon') {
            const metric = referenceTokens.controlMetrics?.[p.size || 'md'];
            const icons = { xs: 12, sm: 14, md: 16, lg: 18, xl: 20, '2xl': 24, '3xl': 32 };
            s.width = s.height = size(
                typeof p.size === 'number' ? p.size : icons[p.size || 'md'] || 16,
            );
        }
        if (p.opacity != null) s.opacity = String(p.opacity);
        if (p.lineHeight != null) s.lineHeight = size(p.lineHeight);
        if (p.position) s.position = p.position;
        if (p.inset != null) s.inset = size(p.inset);
        if (p.fontSize)
            s.fontSize =
                p.fontSize === 'fill'
                    ? size((referenceTokens.controlMetrics?.[p.size || 'xl']?.height || 40) * 0.75)
                    : size(p.fontSize);
        if (p.shadow) s.boxShadow = '0 4px 20px #00000012';
        for (const key of [
            'margin',
            'marginTop',
            'marginRight',
            'marginBottom',
            'marginLeft',
            'paddingTop',
            'paddingRight',
            'paddingBottom',
            'paddingLeft',
        ])
            if (p[key] != null) spacing(s, key, p[key]);
        if (p.id) el.id = String(p.id);
        if (p.ariaLabel) el.setAttribute('aria-label', p.ariaLabel);
        if (p.ariaHidden != null) el.setAttribute('aria-hidden', String(p.ariaHidden));
        if (p.accessibilityId) el.id = String(p.accessibilityId);
        if (p.theme) {
            el.dataset.theme = p.theme;
            if (!p.color) s.color = color('primary');
        }
        if (p.rtl != null) s.direction = p.rtl ? 'rtl' : 'ltr';
        if (p.role) el.setAttribute('role', p.role);
        if (p.tooltip) el.title = p.tooltip;
        if (p.variant) el.dataset.variant = p.variant;
    }
    const tags = {
        text: 'div',
        title: 'h2',
        caption: 'small',
        label: 'label',
        bold: 'strong',
        italic: 'em',
        underline: 'u',
        strikethrough: 's',
        code: 'code',
        blockquote: 'blockquote',
        button: 'button',
        pressable: 'button',
        input: 'input',
        textarea: 'textarea',
        slider: 'input',
        checkbox: 'label',
        select: 'select',
        'segmented-control': 'div',
        'radio-group': 'fieldset',
        radio: 'input',
        'date-picker': 'input',
        form: 'form',
        table: 'table',
        'table-section': 'tbody',
        'table-row': 'tr',
        'table-cell': 'td',
        list: 'ol',
        'list-item': 'li',
        divider: 'hr',
        Link: 'button',
        Entity: 'button',
        Cite: 'button',
        FileCite: 'button',
        CodeCite: 'button',
        FollowUp: 'button',
        CodeBlock: 'pre',
        WritingBlock: 'section',
        AsyncVideo: 'video',
    };
    // Intrinsics are explicit data transforms; strings never become executable expressions.
    function intrinsic(type, p, children, path) {
        if (type === 'Scope')
            return node(children, path + '.scope', false, { ...renderScope, ...p.values });
        if (type === 'Show') {
            const fallback = children.filter((child) => child?.type === 'Show.Else');
            return node(
                (p.when ?? true)
                    ? children.filter((child) => child?.type !== 'Show.Else')
                    : fallback,
                path + '.show',
            );
        }
        if (type === 'Show.Else') return node(children, path + '.else');
        const items = p.items ?? p.of;
        if (items == null) return document.createTextNode('');
        if (!Array.isArray(items)) throw Error('Each.items or Each.of must be an array');
        const fragment = document.createDocumentFragment();
        items.forEach((item, index) => {
            const scope = {
                ...renderScope,
                [p.itemName || p.item || p.as || 'item']: item,
                [p.indexName || p.index || p.indexAs || 'index']: index,
            };
            const key = p.keyField ? readPath(item, p.keyField) : index;
            fragment.append(node(children, `${path}.each.${key}`, false, scope));
        });
        return fragment;
    }

    // Safe Markdown: build native DOM nodes, never inject HTML from model output.
    function markdown(source, plain = false) {
        const container = document.createElement('div');
        container.className = 'genui-markdown';
        if (/\$|\\\(|\\\[/.test(source)) markMath(container, JSON.stringify([source, plain]));
        if (global.markdownit) {
            const parser = global.markdownit({ html: false, linkify: true, breaks: false });
            const stack = [container];
            const renderTokens = (tokens) => {
                for (const token of tokens) {
                    const parent = stack[stack.length - 1];
                    if (token.type === 'inline') {
                        renderTokens(token.children || []);
                        continue;
                    }
                    if (token.nesting === -1) {
                        stack.pop();
                        continue;
                    }
                    if (
                        token.type === 'text' ||
                        token.type === 'html_inline' ||
                        token.type === 'html_block'
                    ) {
                        parent.append(document.createTextNode(token.content));
                        continue;
                    }
                    if (token.type === 'softbreak') {
                        parent.append(document.createTextNode('\n'));
                        continue;
                    }
                    if (token.type === 'hardbreak') {
                        parent.append(document.createElement('br'));
                        continue;
                    }
                    if (token.type === 'image') {
                        const url = safeURL(token.attrGet('src'));
                        if (!plain && url) {
                            const image = document.createElement('img');
                            image.src = url;
                            image.alt = token.content;
                            parent.append(image);
                        } else parent.append(document.createTextNode(token.content));
                        continue;
                    }
                    if (['fence', 'code_block'].includes(token.type)) {
                        const pre = document.createElement('pre'),
                            code = document.createElement('code');
                        code.textContent = token.content;
                        pre.append(code);
                        parent.append(pre);
                        continue;
                    }
                    if (token.type === 'code_inline') {
                        const code = document.createElement('code');
                        code.textContent = token.content;
                        parent.append(code);
                        continue;
                    }
                    const tags = new Set([
                        'p',
                        'h1',
                        'h2',
                        'h3',
                        'h4',
                        'h5',
                        'h6',
                        'blockquote',
                        'ul',
                        'ol',
                        'li',
                        'strong',
                        'em',
                        's',
                        'table',
                        'thead',
                        'tbody',
                        'tr',
                        'th',
                        'td',
                        'hr',
                    ]);
                    if (token.type === 'link_open') {
                        const url = safeURL(token.attrGet('href')),
                            link = document.createElement(url && !plain ? 'button' : 'span');
                        if (url && !plain) {
                            link.type = 'button';
                            link.className = 'genui-inline-link';
                            listen(link, 'click', (event) =>
                                action({ type: 'openUrl', url }, null, event),
                            );
                        }
                        parent.append(link);
                        stack.push(link);
                        continue;
                    }
                    if (!tags.has(token.tag)) continue;
                    const element = document.createElement(token.tag);
                    if (token.tag === 'ol' && token.attrGet('start'))
                        element.setAttribute('start', token.attrGet('start'));
                    parent.append(element);
                    if (token.nesting === 1) stack.push(element);
                }
            };
            renderTokens(parser.parse(String(source), {}));
            return container;
        }
        function inline(text, parent) {
            const pattern = /(`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*|~~[^~]+~~|\[[^\]]+\]\([^\s)]+\))/g;
            let start = 0;
            for (const match of text.matchAll(pattern)) {
                parent.append(document.createTextNode(text.slice(start, match.index)));
                start = match.index + match[0].length;
                const token = match[0];
                let element;
                if (token.startsWith('[')) {
                    const parts = token.match(/^\[([^\]]+)\]\(([^)]+)\)$/),
                        url = safeURL(parts[2]);
                    element = document.createElement(url && !plain ? 'button' : 'span');
                    element.textContent = parts[1];
                    if (url && !plain) {
                        element.type = 'button';
                        element.className = 'genui-inline-link';
                        listen(element, 'click', (event) =>
                            action({ type: 'openUrl', url }, null, event),
                        );
                    }
                } else {
                    const marker = token.startsWith('**') || token.startsWith('~~') ? 2 : 1;
                    element = document.createElement(
                        token[0] === '`'
                            ? 'code'
                            : token.startsWith('**')
                              ? 'strong'
                              : token.startsWith('~~')
                                ? 's'
                                : 'em',
                    );
                    element.textContent = token.slice(marker, -marker);
                }
                parent.append(element);
            }
            parent.append(document.createTextNode(text.slice(start)));
        }
        const lines = String(source).split('\n');
        let list = null;
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.startsWith('```')) {
                const pre = document.createElement('pre'),
                    code = document.createElement('code');
                const language = line.slice(3).trim();
                if (language) pre.dataset.language = language;
                const block = [];
                while (++i < lines.length && !lines[i].startsWith('```')) block.push(lines[i]);
                code.textContent = block.join('\n');
                pre.append(code);
                container.append(pre);
                list = null;
                continue;
            }
            if (!line.trim()) {
                list = null;
                continue;
            }
            const heading = line.match(/^(#{1,6})\s+(.+)$/),
                item = line.match(/^\s*(?:[-*+]\s+|\d+[.)]\s+)(.+)$/);
            if (item) {
                const ordered = /^\s*\d/.test(line),
                    tag = ordered ? 'ol' : 'ul';
                if (!list || list.tagName !== tag.toUpperCase()) {
                    list = document.createElement(tag);
                    container.append(list);
                }
                const li = document.createElement('li');
                inline(item[1], li);
                list.append(li);
                continue;
            }
            list = null;
            if (/^\s*(---+|\*\*\*+)\s*$/.test(line)) {
                container.append(document.createElement('hr'));
                continue;
            }
            const block = document.createElement(
                heading
                    ? 'h' + Math.min(heading[1].length + 1, 6)
                    : line.startsWith('> ')
                      ? 'blockquote'
                      : 'p',
            );
            inline(heading ? heading[2] : line.replace(/^> /, ''), block);
            container.append(block);
        }
        return container;
    }

    function extendedElement(type, p, children, path, el, originalType) {
        const append = () =>
            children.forEach((child, index) =>
                el.append(node(child, `${path}.${child?.props?.key ?? index}`)),
            );
        if (type === 'run-interval') {
            return node(
                h(function RunInterval() {
                    const ticks = DIL.useRef(0);
                    DIL.useEffect(() => {
                        if (p.running === false || !p.onTickAction) return;
                        const interval = Number.isFinite(p.interval)
                            ? Math.max(1, Math.round(p.interval))
                            : 1000;
                        let timer;
                        const tick = () => {
                            if (p.maxTicks != null && ticks.current >= p.maxTicks) {
                                global.clearInterval(timer);
                                return;
                            }
                            ticks.current++;
                            const result = action(
                                p.onTickAction,
                                { tick: ticks.current, time: Date.now() },
                                null,
                            );
                            if (result?.then)
                                result.then((value) => {
                                    if (value?.status === 'unsupported')
                                        global.clearInterval(timer);
                                });
                        };
                        timer = global.setInterval(tick, interval);
                        if (p.leadingTick) tick();
                        return () => global.clearInterval(timer);
                    }, [p.running, p.interval, p.maxTicks]);
                    return children;
                }, {}),
                path + '.interval',
            );
        }
        if (type === 'audio-player') {
            const url = safeURL(p.src);
            if (!url) return missing(el, 'AudioPlayer requires an explicit HTTPS source');
            el.className = 'genui-audio-player';
            if (p.title) el.append(node(h('text', { strong: true }, p.title), path + '.title'));
            if (p.subtitle) el.append(node(h('caption', {}, p.subtitle), path + '.subtitle'));
            const audio = document.createElement('audio');
            audio.src = url;
            audio.controls = true;
            audio.loop = !!p.loop;
            audio.muted = !!p.muted;
            audio.preload = p.preload || 'metadata';
            audio.playbackRate = p.defaultPlaybackRate || 1;
            if (p.initialCurrentTimeSeconds)
                listen(audio, 'loadedmetadata', () => {
                    audio.currentTime = p.initialCurrentTimeSeconds;
                });
            if (p.autoPlay) listen(audio, 'canplay', () => audio.play?.().catch(() => {}));
            el.append(audio);
            if (p.playbackRates?.length)
                el.append(
                    node(
                        h('select', {
                            ariaLabel: 'Playback speed',
                            value: p.defaultPlaybackRate || 1,
                            options: p.playbackRates.map((value) => ({
                                value,
                                label: value + '×',
                            })),
                            onChange: (value) => (audio.playbackRate = Number(value)),
                        }),
                        path + '.speed',
                    ),
                );
            if (p.downloadUrl)
                el.append(
                    node(
                        h('Link', { url: p.downloadUrl, title: p.downloadFilename || 'Download' }),
                        path + '.download',
                    ),
                );
            return el;
        }
        if (type === 'markdown' || type === 'text-only-markdown')
            return markdown(p.text ?? p.value ?? children.join(''), type === 'text-only-markdown');
        // Older generated documents put Markdown prose in Text. Render its formatting
        // without changing SVG labels, literal whitespace, or composed inline nodes.
        if (type === 'text' && !p.preserveWhitespace && children.every(c => typeof c === 'string')) {
            const source = children.map(c => interpolate(c, renderScope)).join('');
            if (/^ {0,3}(?:#{1,6}\s|`{3,}|~{3,}|>\s|[-*+]\s|\d+[.)]\s)/m.test(source) ||
                /\*\*[^*]+\*\*|`[^`\n]+`|\[[^\]]+\]\([^\s)]+\)/.test(source)) {
                const formatted = markdown(source);
                formatted.dataset.nodePath = path;
                return formatted;
            }
        }
        if (type === 'highlight') {
            el = document.createElement('mark');
            append();
            return el;
        }
        if (['transparent', 'component-content', 'DIL_RENDERED_PROP_ELEMENT_TYPE'].includes(type))
            return node(p.content ?? p.value ?? children, path + '.content');
        if (type === 'component' || type === 'CLIENT_DEFINED_WIDGET_TYPE') {
            if (referenceFactories[p.name])
                return node(h(referenceComponent(p.name), p.props || p), path + '.reference');
            if (p.content || children.length)
                return node(p.content || children, path + '.component');
            return missing(el, `Component unavailable: ${p.name || 'no content supplied'}`);
        }
        if (
            [
                'loading',
                'loading-indicator',
                'loading-block',
                'pulse-indicator',
                'shimmer-text',
            ].includes(type)
        ) {
            el.setAttribute('role', 'status');
            el.setAttribute('aria-live', 'polite');
            el.setAttribute('aria-busy', 'true');
            if (type === 'loading-block') {
                el.setAttribute('aria-label', p.label || 'Loading');
                for (let i = 0; i < Math.min(12, Math.max(1, Number(p.lines) || 3)); i++) {
                    const line = document.createElement('span');
                    line.className = 'genui-skeleton-line';
                    line.style.width = i === Number(p.lines || 3) - 1 ? '62%' : '100%';
                    el.append(line);
                }
            } else if (type === 'shimmer-text') {
                el.textContent = p.text ?? p.value ?? children.join('');
            } else {
                const indicator = document.createElement('span');
                indicator.className =
                    type === 'pulse-indicator' ? 'genui-pulse-dot' : 'genui-spinner';
                indicator.setAttribute('aria-hidden', 'true');
                el.append(indicator);
                if (p.label) el.append(document.createTextNode(p.label));
                else el.setAttribute('aria-label', 'Loading');
            }
            return el;
        }
        if (['animate', 'animate-group', 'animate-item', 'transition'].includes(type)) {
            el.dataset.nodePath = path;
            append();
            const frame = (value = {}) => {
                const result = {};
                if (value.opacity != null) result.opacity = value.opacity;
                const transform = [];
                for (const key of [
                    'x',
                    'y',
                    'translateX',
                    'translateY',
                    'rotate',
                    'rotateY',
                    'scale',
                    'scaleX',
                    'scaleY',
                    'perspective',
                ]) {
                    if (value[key] == null) continue;
                    const name = { x: 'translateX', y: 'translateY', rotate: 'rotate' }[key] || key;
                    const unit = ['rotate', 'rotateY'].includes(key)
                        ? 'deg'
                        : ['scale', 'scaleX', 'scaleY'].includes(key)
                          ? ''
                          : 'px';
                    transform.push(
                        `${name}(${typeof value[key] === 'number' ? value[key] + unit : value[key]})`,
                    );
                }
                if (transform.length) result.transform = transform.join(' ');
                return result;
            };
            el.__motionKey = JSON.stringify([p.initial, p.enter, p.name, p.key, p.duration, p.delay, p.preventInitialTransition]);
            el.__motion = null;
            effects.push(() => {
                const target = liveElement(el);
                if (target.__motion) return;
                if (
                    global.matchMedia?.('(prefers-reduced-motion: reduce)').matches ||
                    p.preventInitialTransition
                )
                    return;
                const initial = frame(p.initial || { opacity: 0 }),
                    enter = frame(p.enter || { opacity: 1 });
                const options = {
                    duration: p.enter?.duration ?? p.duration ?? 240,
                    delay: p.enter?.delay ?? p.delay ?? 0,
                    easing: p.enter?.timingFunction || 'ease',
                    fill: 'both',
                };
                if (target.animate) target.__motion = target.animate([initial, enter], options);
            });
            return el;
        }
        if (type === 'flashcard-flip') {
            const key = p.bind || `@flip:${path}:${p.activeKey || ''}`;
            const controlled = p.flipped != null && !p.bind && !p.front;
            const flipped = controlled
                ? !!p.flipped
                : Object.hasOwn(state, key)
                  ? !!state[key]
                  : !!p.flipped;
            el = document.createElement('div');
            el.className = 'genui-flashcard-flip';
            el.dataset.flipped = String(flipped);
            if (p.reducedMotion) el.dataset.reducedMotion = 'true';
            const inner = document.createElement('div');
            inner.className = 'genui-flashcard-inner';
            for (const back of [false, true]) {
                const face = document.createElement('div');
                face.className = 'genui-flashcard-face' + (back ? ' genui-flashcard-back' : '');
                face.setAttribute('aria-hidden', String(back !== flipped));
                face.inert = back !== flipped;
                face.append(
                    node(
                        back ? (p.back ?? children[1]) : (p.front ?? children[0]),
                        path + (back ? '.back' : '.front'),
                    ),
                );
                inner.append(face);
            }
            for (let index = children.length - 1; index >= 2; index--) {
                const card = document.createElement('div');
                card.className = 'genui-flashcard-stack';
                card.setAttribute('aria-hidden', 'true');
                card.inert = true;
                card.style.transform = `translateY(${(index - 1) * 12}px) rotate(-1.25deg) scale(${Math.pow(0.96, index - 1)})`;
                card.append(
                    node(children[index], `${path}.stack.${children[index]?.props?.key ?? index}`),
                );
                el.append(card);
            }
            el.append(inner);
            const signature = JSON.stringify([
                flipped,
                p.activeKey,
                p.shuffleKey,
                p.dismissDirection,
                p.restoreDirection,
            ]);
            const previous = flashcardMotions.get(path);
            if (previous && previous.signature !== signature) {
                clearTimeout(previous.timer);
                const motion = { signature, timer: null };
                flashcardMotions.set(path, motion);
                effects.push(() => {
                    const reduced =
                        p.reducedMotion ||
                        global.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
                    action(p.onInteractionChange, !reduced, null);
                    if (!reduced)
                        motion.timer = setTimeout(() => {
                            if (flashcardMotions.get(path) === motion)
                                action(p.onInteractionChange, false, null);
                        }, 600);
                });
            } else if (!previous) flashcardMotions.set(path, { signature });
            if (!controlled) {
                el.tabIndex = 0;
                el.setAttribute('role', 'button');
                el.setAttribute('aria-pressed', String(flipped));
                el.setAttribute(
                    'aria-label',
                    p.ariaLabel ||
                        `${inner.children[flipped ? 1 : 0].textContent}. ${p.label || 'Tap to flip'}`,
                );
                const flip = (event) => {
                    if (p.disabled) return;
                    state[key] = !flipped;
                    action(p.onChange, !flipped, event);
                    queueRender();
                };
                listen(el, 'click', flip);
                listen(el, 'keydown', (event) => {
                    if (['Enter', ' '].includes(event.key)) {
                        event.preventDefault();
                        flip(event);
                    }
                });
            }
            listen(el, 'pointerdown', (event) => {
                if (!p.disabled) {
                    const target = liveElement(el);
                    swipeStates.set(target, {startX:event.clientX, pointerId:event.pointerId});
                    target.setPointerCapture?.(event.pointerId);
                }
            });
            listen(el, 'pointermove', (event) => {
                const target = liveElement(el), drag = swipeStates.get(target);
                if (drag && drag.pointerId === event.pointerId) {
                    const progress =
                        (event.clientX - drag.startX) / Math.max(1, target.getBoundingClientRect().width);
                    action(p.onSwipeProgress, progress, event);
                }
            });
            listen(el, 'pointerup', (event) => {
                const target = liveElement(el), drag = swipeStates.get(target);
                if (!drag || drag.pointerId !== event.pointerId) return;
                const delta = event.clientX - drag.startX;
                swipeStates.delete(target);
                if (target.hasPointerCapture?.(event.pointerId)) target.releasePointerCapture(event.pointerId);
                if (Math.abs(delta) > 60)
                    action(delta < 0 ? p.onSwipeLeft : p.onSwipeRight, null, event);
                action(p.onSwipeProgress, 0, event);
            });
            listen(el, 'pointercancel', (event) => {
                const target = liveElement(el), drag = swipeStates.get(target);
                if (drag?.pointerId !== event.pointerId) return;
                swipeStates.delete(target);
                action(p.onSwipeProgress, 0, event);
            });
            return el;
        }
        if (type === 'choice') {
            el = document.createElement('button');
            el.type = 'button';
            el.className = 'genui-choice';
            el.disabled = !!p.disabled;
            el.setAttribute('aria-pressed', String(!!p.selected));
            el.textContent = p.label || '';
            append();
            listen(el, 'click', (event) => action(p.onClick, p.value, event));
            return el;
        }
        if (type === 'tooltip') {
            el.title = p.text || p.label || '';
            el.setAttribute('aria-label', el.title);
            el.tabIndex = 0;
            append();
            return el;
        }
        if (type === 'celebration') {
            el.setAttribute('role', 'status');
            el.setAttribute('aria-live', 'polite');
            if (p.active === false) return document.createTextNode('');
            el.append(
                node(h('icon', { name: 'check', color: 'success' }), path + '.check'),
                document.createTextNode(p.label || 'Complete'),
            );
            append();
            return el;
        }
        if (type === 'lottie') {
            if (!global.lottie) return missing(el, 'Animation player failed to load');
            const data = p.animationData || p.data,
                url = safeURL(p.src || p.url);
            if (!data && !url) return missing(el, p.fallback || 'Animation data is missing');
            el.className = 'genui-lottie';
            el.dataset.nodePath = path;
            el.__animationKey = JSON.stringify([data, url, p.loop, p.autoplay]);
            if (data?.w > 0 && data?.h > 0) el.style.aspectRatio = `${data.w} / ${data.h}`;
            // Mount only once the reconciled element is in the live document.
            effects.push(() => {
                const target = liveElement(el);
                target.__lottieProps = p;
                if (target.__animation) {
                    target.__animation.setSpeed(p.speed ?? 1);
                    return;
                }
                const animation = global.lottie.loadAnimation({
                    container: target,
                    renderer: 'svg',
                    loop: p.loop ?? true,
                    autoplay:
                        p.autoplay !== false &&
                        !global.matchMedia?.('(prefers-reduced-motion: reduce)').matches,
                    ...(data ? { animationData: clone(data) } : { path: url }),
                });
                target.__animation = animation;
                animation.addEventListener('data_failed', () =>
                    missing(el, p.fallback || 'Animation could not be loaded'),
                );
                if (p.speed != null) animation.setSpeed(p.speed);
                animation.addEventListener('complete', () => action(target.__lottieProps.onComplete, null, null));
                animation.addEventListener('DOMLoaded', () => {
                    if (animation.animationData?.w > 0)
                        el.style.aspectRatio = `${animation.animationData.w} / ${animation.animationData.h}`;
                    reportLayout();
                });
            });
            return el;
        }
        if (type === 'youtube') {
            let id = String(p.videoId || p.id || '');
            const url = safeURL(p.url);
            if (url) {
                const parsed = new URL(url);
                id =
                    parsed.hostname === 'youtu.be'
                        ? parsed.pathname.slice(1)
                        : parsed.searchParams.get('v') || parsed.pathname.split('/').pop();
            }
            if (!/^[A-Za-z0-9_-]{11}$/.test(id)) return missing(el, 'YouTube video ID is missing');
            el.className = 'genui-youtube-player';
            el.dataset.nodePath = path;
            el.style.aspectRatio = p.aspectRatio || '16 / 9';
            el.style.width = p.width || '100%';
            const key = `video-${path}:${id}`;
            videos.push({
                id: key,
                videoId: id,
                title: p.title || 'YouTube',
                poster: !!p.showThumbnail,
                el,
                props: p,
            });
            if (p.onHover) listen(el, 'mouseenter', (event) => action(p.onHover, null, event));
            if (p.showThumbnail)
                listen(el, 'click', (event) => {
                    if (!el.parentElement?.closest?.('.genui-pressable'))
                        action(
                            () =>
                                guarded('openVideoLightbox', {
                                    args: { video_id: id, title: p.title },
                                }),
                            null,
                            event,
                        );
                });
            return el;
        }
        if (type === 'horizontal-swipe-surface') {
            el.className = 'genui-carousel';
            el.style.scrollSnapType = p.snap === false ? 'none' : 'x mandatory';
            append();
            return el;
        }
        if (type === 'follow-up-action-bar') {
            el.setAttribute('role', 'group');
            append();
            return el;
        }
        return null;
    }

    let renderScope = state,
        renderTheme = global.__GENUI_THEME__ || 'light';
    function node(value, path = '0', svg = false, scope = renderScope) {
        const previous = renderScope,
            previousTheme = renderTheme;
        renderScope = scope;
        if (value?.props?.theme) renderTheme = value.props.theme;
        try {
            return renderNode(value, path, svg);
        } catch (error) {
            bridge({ type: 'warning', path, message: String(error.message) });
            const el = document.createElement('div');
            el.setAttribute('role', 'status');
            return missing(el, `This section could not be rendered: ${error.message}`);
        } finally {
            renderScope = previous;
            renderTheme = previousTheme;
        }
    }
    function renderNode(value, path, svg) {
        if (value == null || value === false) return document.createTextNode('');
        if (Array.isArray(value)) {
            const f = document.createDocumentFragment();
            value.forEach((v, i) => f.append(node(v, `${path}.${v?.props?.key ?? i}`, svg)));
            return f;
        }
        if (typeof value !== 'object')
            return document.createTextNode(interpolate(String(value), renderScope));
        if (typeof value.type === 'function') {
            const prev = current,
                idx = hookIndex;
            current = `${path}:${value.props?.key ?? ''}`;
            hookIndex = 0;
            try {
                return node(
                    value.type({ ...value.props, children: value.children }),
                    `${path}.component`,
                    svg,
                );
            } finally {
                current = prev;
                hookIndex = idx;
            }
        }
        if (referenceFactories[value.type])
            return node(
                h(referenceComponent(value.type), value.props, value.children || []),
                path + '.reference',
                svg,
            );
        const originalType = value.type,
            type = canonicalType(originalType),
            p = Object.fromEntries(
                Object.entries(value.props || {}).map(([k, v]) =>
                    k.startsWith('$')
                        ? [k.slice(1), evaluateCEL(v, renderScope)]
                        : [k, resolve(v, renderScope)],
                ),
            );
        let children = value.children || p.children || [];
        if (!Array.isArray(children)) children = [children];
        if (
            p.value != null &&
            [
                'text',
                'title',
                'caption',
                'label',
                'bold',
                'italic',
                'underline',
                'strikethrough',
                'code',
            ].includes(type)
        )
            children = [p.value];
        if (p.visible === false) return document.createTextNode('');
        if (p.bind && Object.hasOwn(state, p.bind))
            p[type === 'checkbox' ? 'checked' : 'value'] = state[p.bind];
        const svgTags = new Set([
            'svg',
            'g',
            'path',
            'circle',
            'ellipse',
            'rect',
            'line',
            'polyline',
            'polygon',
            'text',
            'defs',
            'linearGradient',
            'radialGradient',
            'stop',
            'clipPath',
        ]);
        if (svg || type === 'svg') {
            if (!svgTags.has(type)) return document.createTextNode('Unsupported SVG element');
            const e = document.createElementNS(SVG_NS, type);
            for (const [k, v] of Object.entries(p))
                if (
                    /^(viewBox|width|height|fill|stroke|fillOpacity|fillRule|strokeOpacity|strokeDasharray|strokeDashoffset|strokeMiterlimit|strokeWidth|strokeLinecap|strokeLinejoin|preserveAspectRatio|color|x|y|x1|x2|y1|y2|cx|cy|r|rx|ry|d|points|transform|opacity|offset|stopColor|stopOpacity|gradientUnits|gradientTransform|spreadMethod|pathLength|id|clipPath|fontSize|fontFamily|fontWeight|textAnchor|dominantBaseline)$/.test(
                        k,
                    )
                )
                    e.setAttribute(
                        [
                            'viewBox',
                            'preserveAspectRatio',
                            'gradientUnits',
                            'gradientTransform',
                            'spreadMethod',
                            'pathLength',
                        ].includes(k)
                            ? k
                            : k.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase()),
                        String(v),
                    );
            children.forEach((c, i) => e.append(node(c, `${path}.${i}`, true)));
            return e;
        }
        if (['Each', 'Scope', 'Show', 'Show.Else'].includes(type))
            return intrinsic(type, p, children, path);
        let el = document.createElement(tags[type] || 'div');
        el.className = `genui-${type}`;
        el.dataset.nodePath = path;
        if (type !== 'slider') style(el, p, type);
        if (!names.includes(type)) return missing(el, `Unsupported component: ${String(type)}`);
        const extension = extendedElement(type, p, children, path, el, originalType);
        if (extension) {
            if (extension.style) style(extension, p, type);
            return extension;
        }
        if (type === 'grid' || type === 'flow') {
            el.style.display = p.layout === 'row' ? 'flex' : 'grid';
            el.style.gridTemplateColumns = p.minChildWidth
                ? `repeat(auto-fit,minmax(min(100%,${size(p.minChildWidth)}),1fr))`
                : `repeat(${Number(p.columns) || 2},minmax(0,1fr))`;
            if (p.rows) el.style.gridTemplateRows = `repeat(${p.rows},auto)`;
        }
        if (type === 'grid-item' || type === 'flow-item') {
            if (p.span) el.style.gridColumn = `span ${p.span}`;
            if (p.rowSpan) el.style.gridRow = `span ${p.rowSpan}`;
            if (p.aspectMode) el.style.objectFit = p.aspectMode;
        }
        if (type === 'divider') {
            if (p.spacing)
                el.style.margin = `${global.innerWidth < 640 ? compactSpacing(p.spacing, 12) : size(p.spacing, true)} 0`;
            if (p.size) el.style.borderTopWidth = size(p.size);
            if (p.color) el.style.borderColor = p.color;
        }
        if (type === 'spacer') {
            el.style.flex = p.flex == null ? '1' : String(p.flex);
        }
        if (type === 'math') {
            const source = p.value ?? children.join('');
            el.textContent = global.MathJax
                ? p.block
                    ? '\\[' + source + '\\]'
                    : '\\(' + source + '\\)'
                : source;
            markMath(el, el.textContent);
            el.classList.add(p.block ? 'math-block' : 'math-inline');
            if (!global.MathJax) el.title = 'Math source (typesetting engine unavailable)';
            return el;
        }
        if (type === 'icon') {
            const icons = {
                check: 'm5 12 4 4L19 6',
                close: 'm6 6 12 12M6 18 18 6',
                plus: 'M12 5v14M5 12h14',
                minus: 'M5 12h14',
                search: 'M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0',
                heart: 'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8',
                star: 'm12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3 6.4 20.2l1.1-6.2L3 9.6l6.2-.9Z',
                arrowRight: 'M4 12h16m-6-6 6 6-6 6',
                arrowDown: 'M12 4v16m-6-6 6 6 6-6',
                chevronRight: 'm9 5 7 7-7 7',
                info: 'M12 11v6m0-10v.01M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0',
                warning: 'm12 3 10 18H2Zm0 5v6m0 3v.01',
                copy: 'M9 9h12v12H9ZM5 15H3V3h12v2',
                calendar: 'M3 5h18v16H3ZM7 3v4m10-4v4M3 11h18',
                map: 'm3 5 6-2 6 2 6-2v16l-6 2-6-2-6 2Zm6-2v16m6-14v16',
                play: 'm6 3 15 9-15 9Z',
                pause: 'M8 4v16M16 4v16',
                sun: 'M12 1v2m0 18v2M1 12h2m18 0h2M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2M17 12a5 5 0 1 1-10 0 5 5 0 0 1 10 0',
                moon: 'M21 13A9 9 0 0 1 11 3a9 9 0 1 0 10 10',
                refresh: 'M20 7v5h-5M4 17v-5h5M5 7a8 8 0 0 1 13-2l2 2M4 17l2 2a8 8 0 0 0 13-2',
                cpu: 'M6 6h12v12H6ZM9 9h6v6H9ZM9 2v4m6-4v4M9 18v4m6-4v4M2 9h4m-4 6h4m12-6h4m-4 6h4',
                shuffle: 'M4 7h4l8 10h4m-4-4 4 4-4 4M4 17h4l8-10h4m-4-4 4 4-4 4',
                blocks: 'M3 11h8v10H3ZM13 11h8v10h-8ZM13 1h8v8h-8Z',
                layers: 'm12 3 10 5-10 5L2 8Zm-10 9 10 5 10-5M2 16l10 5 10-5',
            };
            const name = String(p.name || '').replace(/-([a-z])/g, (_, c) => c.toUpperCase());
            el.setAttribute('role', 'img');
            el.setAttribute('aria-label', p.name || 'icon');
            const referenceAssets = global.__GENUI_REFERENCE_ICONS__;
            const requested = String(p.name || '').replaceAll('_', '-');
            const alias = referenceAssets?.LUCIDE_FIRST_PARTY_ICON_ALIASES?.[requested];
            const asset = referenceAssets?.icons?.[alias || requested];
            if (asset) {
                const colored = new Set([
                    'slack-logo',
                    'championship-cup',
                    'christmas',
                    'fire',
                    'garden-expo',
                    'jordy',
                    'komi',
                    'loud-speaker',
                    'national-museum',
                    'share-icon',
                    'soccer-ball',
                    'south-korea-flag',
                ]).has(alias || requested);
                const build = (entry, definition = false) => {
                    const result = document.createElementNS(SVG_NS, entry.tag);
                    definition ||= ['defs', 'mask', 'clipPath'].includes(entry.tag);
                    for (const [key, value] of Object.entries(entry.attrs))
                        result.setAttribute(
                            key,
                            !colored &&
                                !definition &&
                                ['fill', 'stroke'].includes(key) &&
                                value !== 'none'
                                ? 'currentColor'
                                : value,
                        );
                    for (const child of entry.children) result.append(build(child, definition));
                    return result;
                };
                el.append(build(asset));
            } else if (icons[name]) {
                const svg = document.createElementNS(SVG_NS, 'svg');
                for (const [key, v] of Object.entries({
                    viewBox: '0 0 24 24',
                    fill: 'none',
                    stroke: 'currentColor',
                    'stroke-width': 1.8,
                    'stroke-linecap': 'round',
                    'stroke-linejoin': 'round',
                    'aria-hidden': 'true',
                }))
                    svg.setAttribute(key, v);
                const path = document.createElementNS(SVG_NS, 'path');
                path.setAttribute('d', icons[name]);
                svg.append(path);
                el.append(svg);
            } else {
                el.textContent = '';
                el.title = `Icon unavailable: ${p.name}`;
                bridge({ type: 'warning', path, message: `Icon unavailable: ${p.name}` });
            }
            if (p.size) {
                el.style.width = size(p.size);
                el.style.height = size(p.size);
            }
            return el;
        }
        if (type === 'favicon') {
            const r = resource(p.url);
            const src = safeURL(r?.src || r?.url);
            return src
                ? node(
                      h('AsyncImage', {
                          src,
                          alt: p.alt || 'Favicon',
                          width: p.size || 16,
                          height: p.size || 16,
                      }),
                      path,
                  )
                : missing(el, 'Favicon unavailable: no explicit image resource');
        }
        if (type === 'AsyncImage' || type === 'AsyncVideo') {
            const r = resource(p.ref),
                url = safeURL(p.src || r?.src || r?.url);
            if (!url)
                return missing(
                    el,
                    p.fallback || `Media unavailable${p.query ? ': ' + p.query : ''}`,
                );
            if (type === 'AsyncImage') {
                el = document.createElement('img');
                el.className = 'genui-AsyncImage';
                style(el, p, type);
                el.alt = p.alt || r?.title || '';
                el.style.objectFit = p.fit || 'cover';
                el.loading = 'lazy';
                if (p.frame) {
                    el.style.border = '1px solid var(--border)';
                    el.style.padding = '4px';
                }
                if (p.group) el.dataset.group = String(p.group);
                listen(el, 'error', () => {
                    el.replaceWith(
                        missing(document.createElement('div'), p.fallback || 'Image unavailable'),
                    );
                });
            } else {
                el.controls = true;
                el.preload = 'metadata';
            }
            el.src = url;
            return el;
        }
        if (type === 'AsyncImageGroup') {
            if (p.size) el.dataset.size = String(p.size);
            const refs = p.refs || (p.ref ? [p.ref] : []);
            if (!refs.length)
                return missing(
                    el,
                    p.fallback || 'Image search unavailable: provide explicit resource references',
                );
            el.style.display = 'grid';
            el.style.gridTemplateColumns = `repeat(${p.layout === 'row' ? refs.length : 2},minmax(0,1fr))`;
            refs.forEach((ref, i) =>
                el.append(node(h('AsyncImage', { ...p, ref }), `${path}.${i}`)),
            );
            return el;
        }
        if (type === 'Chart')
            return chart(
                ['pie-chart', 'PieChart'].includes(originalType)
                    ? {
                          ...p,
                          ...(p.content || {}),
                          chartType: 'pie',
                          data: p.data || p.content?.data,
                          nameKey:
                              p.nameKey ||
                              (typeof p.xAxis === 'string' ? p.xAxis : p.xAxis?.dataKey) ||
                              p.content?.nameKey,
                          valueKey: p.valueKey || p.series?.[0]?.dataKey || p.content?.valueKey,
                      }
                    : p.content || {
                          ...p,
                          chartType: p.chartType || p.series?.[0]?.type || 'line',
                          xKey: typeof p.xAxis === 'string' ? p.xAxis : p.xAxis?.dataKey,
                          yAxisMin: p.yAxis?.min,
                          yAxisMax: p.yAxis?.max,
                      },
                el,
                p,
            );
        if (type === 'MapWidgetV2') {
            el.id = `map-${path.replace(/[^a-z0-9]/gi, '-')}`;
            el.textContent = p.title || 'Map';
            const canvas = document.createElement('div');
            canvas.className = 'genui-map-canvas';
            canvas.style.height = size(Math.min(900, Math.max(180, Number(p.minHeight) || 260)));
            el.append(canvas);
            for (const text of [p.narrative, p.answer])
                if (text) {
                    const description = document.createElement('p');
                    description.textContent = String(text);
                    el.append(description);
                }
            if (Array.isArray(p.points)) {
                const list = document.createElement('ul');
                p.points.forEach((point) => {
                    const item = document.createElement('li');
                    item.textContent =
                        point.title ||
                        point.name ||
                        point.address ||
                        point.query ||
                        `${point.lat ?? point.latitude}, ${point.lng ?? point.longitude}`;
                    list.append(item);
                });
                el.append(list);
            }
            maps.push({ id: el.id, el: canvas, props: p });
            return el;
        }
        if (['Link', 'Entity', 'Cite', 'FileCite', 'CodeCite', 'MemoryCite'].includes(type)) {
            if (type === 'Cite' && Array.isArray(p.refs) && p.refs.length > 1) {
                const list = document.createElement('span');
                list.className = 'genui-citations';
                p.refs.forEach((ref, i) =>
                    list.append(node(h('Cite', { ...p, refs: undefined, ref }), `${path}.${i}`)),
                );
                return list;
            }
            const refs = p.refs || [p.ref || p.citation_id],
                r = resource(refs[0]),
                url = safeURL(p.url || r?.url);
            el.textContent =
                p.title || r?.title || p.value || refs.filter(Boolean).join(', ') || type;
            if (type === 'Entity') {
                listen(el, 'click', (e) =>
                    action({ type: 'openEntityDetail', args: { ...r, ...p } }, null, e),
                );
            } else if (url) {
                listen(el, 'click', (e) => action({ type: 'openUrl', url }, null, e));
            } else if (r?.text) {
                const lines = String(r.text).split('\n');
                const start = Math.max(1, Number(p.line_range_start) || 1),
                    end = Math.max(start, Number(p.line_range_end) || lines.length);
                const excerpt = lines.slice(start - 1, end).join('\n');
                listen(el, 'click', (e) =>
                    action(
                        { type: 'openEntityDetail', args: { ...r, ...p, text: excerpt } },
                        null,
                        e,
                    ),
                );
            } else {
                el.disabled = true;
                el.title = 'Reference unavailable: no resolved resource URL or text';
            }
            if (p.line_range_start)
                el.append(
                    ` · lines ${p.line_range_start}–${p.line_range_end || p.line_range_start}`,
                );
            el.setAttribute('aria-label', p.ariaLabel || el.textContent);
            return el;
        }
        if (type === 'FileNavList') {
            (p.items || []).forEach((item, i) =>
                el.append(
                    node(
                        h('Link', typeof item === 'string' ? { ref: item } : item),
                        `${path}.${i}`,
                    ),
                ),
            );
            return el;
        }
        if (type === 'FollowUp') {
            el.textContent = p.value || p.query || 'Continue';
            listen(el, 'click', (e) =>
                action({ type: 'issueNewTurn', query: p.query || p.value }, null, e),
            );
            return el;
        }
        if (type === 'AppBlock') {
            if (p.content) return node(p.content, `${path}.app`);
            if (children.length) return node(children, `${path}.app`);
            if (typeof p.entrypoint === 'function') return node(h(p.entrypoint, p), `${path}.app`);
            if (p.entrypoint && typeof p.entrypoint === 'object')
                return node(p.entrypoint, `${path}.app`);
            return missing(
                el,
                `${p.title || 'App'}: provide inline content; external entrypoints are unavailable`,
            );
        }
        if (type === 'CodeBlock') {
            const text = children.map((c) => (typeof c === 'string' ? c : '')).join('');
            if (p.editable) {
                el = document.createElement('textarea');
                el.className = 'genui-CodeBlock';
                el.value = p.value ?? text;
                bind(el, p, 'input');
            } else el.textContent = p.value ?? text;
            if (p.interactive || p.model_previewable)
                el.title = 'Client display only; external code execution is unavailable';
            return el;
        }
        if (type === 'WritingBlock' && p.subject) {
            const heading = document.createElement('h3');
            heading.textContent = p.subject;
            el.append(heading);
        }
        if (['button', 'pressable', 'popover-trigger'].includes(type)) {
            if (el.tagName === 'BUTTON') {
                el.type = p.submit ? 'submit' : 'button';
                if (p.uniform) {
                    el.style.width = el.style.height;
                    el.style.padding = '0';
                }
                el.disabled = !!(p.disabled || p.loading);
                if (p.loading) {
                    el.setAttribute('aria-busy', 'true');
                    const spinner = document.createElement('span');
                    spinner.className = 'genui-spinner';
                    spinner.setAttribute('aria-hidden', 'true');
                    el.append(spinner);
                }
                if (p.label) el.append(document.createTextNode(p.label));
            }
            listen(el, 'pointerdown', () => {
                const width = el.getBoundingClientRect().width;
                const scale =
                    width <= 80
                        ? 0.96
                        : width <= 150
                          ? 0.97
                          : width <= 220
                            ? 0.98
                            : width > 600
                              ? 0.995
                              : 0.985;
                el.style.setProperty('--press-scale', scale);
            });
            listen(el, 'click', (e) => action(p.onClick, null, e));
        }
        if (type === 'badge' && p.label) el.textContent = p.label;
        if (p.onHover) listen(el, 'mouseenter', (e) => action(p.onHover, null, e));
        if (type === 'label' && p.htmlFor) el.htmlFor = p.htmlFor;
        if (['input', 'textarea', 'slider', 'date-picker', 'radio'].includes(type)) {
            el.setAttribute(
                'aria-label',
                p.ariaLabel || p.label || p.name || p.placeholder || type,
            );
            if (p.sliderStyle) el.dataset.sliderStyle = String(p.sliderStyle);
            if (type !== 'textarea') {
                el.type =
                    type === 'slider'
                        ? 'range'
                        : type === 'date-picker'
                          ? 'date'
                          : type === 'radio'
                            ? 'radio'
                            : p.inputType || 'text';
            }
            for (const key of ['name', 'placeholder', 'min', 'max', 'step', 'rows', 'id'])
                if (p[key] != null) el[key] = p[key];
            if (p.name && !p.id) el.id = p.name;
            el.disabled = !!p.disabled;
            el.required = !!p.required;
            el.value = p.value ?? p.defaultValue ?? '';
            let sliderControl;
            if (type === 'slider') {
                // Keep the changing fill outside WebKit's native range track.
                // Repainting a gradient in that pseudo-element can flash while
                // WebKit is also updating the native thumb during a drag.
                sliderControl = document.createElement('div');
                sliderControl.className = 'genui-slider-control';
                sliderControl.dataset.nodePath = path;
                if (p.sliderStyle) sliderControl.dataset.sliderStyle = String(p.sliderStyle);
                style(sliderControl, p, type);
                el.dataset.nodePath = `${path}.input`;
                const track = document.createElement('div');
                track.className = 'genui-slider-track';
                track.setAttribute('aria-hidden', 'true');
                const fill = document.createElement('div');
                fill.className = 'genui-slider-fill';
                track.append(fill);
                sliderControl.append(track, el);
                const progress = () => {
                    const min = Number(p.min ?? 0),
                        max = Number(p.max ?? 100),
                        value = Number(el.value);
                    const fraction = max > min ? Math.max(0, Math.min(1, (value - min) / (max - min))) : 0;
                    fill.style.transform = `scaleX(${fraction})`;
                };
                progress();
                listen(el, 'input', progress);
            }
            if (p.invalid) el.setAttribute('aria-invalid', 'true');
            bind(
                el,
                p,
                type === 'slider' || type === 'input' || type === 'textarea' ? 'input' : 'change',
                () =>
                    type === 'slider' || p.inputType === 'number'
                        ? el.value === ''
                            ? ''
                            : Number(el.value)
                        : el.value,
            );
            if (p.autoSelect) listen(el, 'focus', () => el.select?.());
            if (p.mask) {
                el.title = 'Input mask: ' + p.mask;
                listen(el, 'input', () => {
                    const raw = el.value.replace(/[^a-z0-9]/gi, '');
                    let index = 0;
                    el.value = String(p.mask)
                        .split('')
                        .map((ch) =>
                            ['#', '9', 'A', '*'].includes(ch)
                                ? raw[index++] || ''
                                : index < raw.length
                                  ? ch
                                  : '',
                        )
                        .join('');
                    if (p.bind) state[p.bind] = el.value;
                });
            }
            if (type === 'textarea') {
                if (p.maxRows) el.style.maxHeight = `${p.maxRows * 1.6 + 1}em`;
                if (p.autoResize)
                    listen(el, 'input', () => {
                        el.style.height = 'auto';
                        el.style.height = el.scrollHeight + 'px';
                    });
            }
            if (type === 'slider' && p.marks) {
                const list = document.createElement('datalist');
                list.id = `marks-${path}`;
                (Array.isArray(p.marks) ? p.marks : []).forEach((m) => {
                    const o = document.createElement('option');
                    o.value = m.value ?? m;
                    o.label = m.label || '';
                    list.append(o);
                });
                el.setAttribute('list', list.id);
                const wrap = document.createElement('div');
                wrap.className = 'genui-slider-group';
                const labels = document.createElement('div');
                labels.className = 'genui-slider-labels';
                (Array.isArray(p.marks) ? p.marks : []).forEach((m) => {
                    const label = document.createElement('span');
                    label.textContent = m.label ?? String(m.value ?? m);
                    labels.append(label);
                });
                wrap.append(sliderControl, list, labels);
                return wrap;
            }
            if (type === 'date-picker' && p.clearable) {
                const wrapper = document.createElement('div');
                wrapper.className = 'genui-date-wrapper';
                const clear = document.createElement('button');
                clear.type = 'button';
                clear.textContent = 'Clear';
                clear.setAttribute('aria-label', 'Clear date');
                clear.disabled = !!p.disabled;
                listen(clear, 'click', (e) => {
                    el.value = '';
                    if (p.bind) {
                        state[p.bind] = '';
                        queueRender();
                    }
                    action(p.onChange, '', e);
                });
                wrapper.append(el, clear);
                return wrapper;
            }
            return sliderControl || el;
        }
        if (type === 'checkbox') {
            const input = document.createElement('input');
            input.type = 'checkbox';
            input.checked = !!(p.checked ?? p.defaultChecked);
            input.disabled = !!p.disabled;
            input.required = !!p.required;
            input.name = p.name || '';
            if (p.id) input.id = p.id;
            input.setAttribute('aria-label', p.ariaLabel || p.label || p.name || 'Checkbox');
            input.value = p.value ?? 'on';
            if (p.lineThrough && input.checked) el.style.textDecoration = 'line-through';
            listen(input, 'change', () => {
                if (p.lineThrough)
                    el.style.textDecoration = input.checked ? 'line-through' : 'none';
            });
            if (p.shape === 'square') input.style.borderRadius = '3px';
            bind(input, p, 'change', () => input.checked);
            el.append(input, document.createTextNode(p.label || ''));
            return el;
        }
        if (type === 'select') {
            if (p.placeholder || p.clearable) {
                const o = document.createElement('option');
                o.value = '';
                o.textContent = p.placeholder || 'None';
                el.append(o);
            }
            (p.options || []).forEach((o) => {
                const option = document.createElement('option');
                option.value = typeof o === 'object' ? o.value : o;
                option.textContent = typeof o === 'object' ? o.label : o;
                option.disabled = !!o.disabled;
                el.append(option);
            });
            el.value = p.value ?? p.defaultValue ?? '';
            el.disabled = !!p.disabled;
            el.required = !!p.required;
            el.name = p.name || '';
            el.setAttribute(
                'aria-label',
                p.ariaLabel || p.label || p.name || p.placeholder || 'Select',
            );
            if (p.icon) el.title = String(p.icon);
            bind(el, p, 'change', () => {
                const selected = (p.options || []).find(
                    (option) =>
                        String(typeof option === 'object' ? option.value : option) === el.value,
                );
                return selected === undefined
                    ? el.value
                    : typeof selected === 'object'
                      ? selected.value
                      : selected;
            });
            return el;
        }
        if (type === 'segmented-control' || type === 'radio-group') {
            if (p.label) {
                const label = document.createElement('legend');
                label.textContent = p.label;
                el.append(label);
            }
            let options =
                p.options ||
                children.map((c) => ({
                    value: c.props?.value,
                    label: c.props?.label || c.children?.join(''),
                    disabled: c.props?.disabled,
                    required: c.props?.required,
                    id: c.props?.id,
                }));
            options.forEach((o, i) => {
                o = typeof o === 'object' ? o : { value: o, label: o };
                const label = document.createElement('label'),
                    input = document.createElement('input');
                input.type = 'radio';
                input.name = p.name || `group-${path}`;
                input.dataset.nodePath = `${path}.option.${i}`;
                input.setAttribute('aria-label', String(o.label ?? o.value));
                input.value = o.value;
                input.checked = String(p.value ?? p.defaultValue) === String(o.value);
                input.required = !!(p.required || o.required);
                if (o.id) input.id = o.id;
                input.disabled = !!(p.disabled || o.disabled);
                bind(input, p, 'change', () => o.value);
                label.append(input, document.createTextNode(o.label ?? o.value));
                el.append(label);
            });
            return el;
        }
        if (type === 'form')
            listen(el, 'submit', (e) => {
                e.preventDefault();
                action(p.onSubmit, Object.fromEntries(new FormData(el)), e);
            });
        if (type === 'table') {
            if (p.columnSizing === 'fixed') el.style.tableLayout = 'fixed';
            if (!children.length) return missing(el, p.emptyLabel || 'No rows');
            if (p.stickyHeader) el.classList.add('sticky-header');
            if (p.dividers === false) el.classList.add('no-dividers');
        }
        if (type === 'table-section' && p.header) {
            const tr = document.createElement('tr'),
                th = document.createElement('th');
            th.colSpan = 100;
            th.textContent = p.header;
            tr.append(th);
            el.append(tr);
        }
        if (type === 'table-section' && p.rowDivider === false) el.classList.add('no-dividers');
        if (type === 'table-row' && p.label) {
            const th = document.createElement('th');
            th.textContent = p.label;
            th.colSpan = p.labelColSpan || 1;
            el.append(th);
        }
        if (type === 'table-row' && p.header) el.classList.add('header-row');
        if (type === 'table-cell') {
            if (p.header) {
                el = document.createElement('th');
                style(el, p, type);
            }
            el.colSpan = p.colSpan || 1;
            el.rowSpan = p.rowSpan || 1;
            if (p.align) el.style.textAlign = p.align;
            if (p.vAlign) el.style.verticalAlign = p.vAlign;
        }
        if (type === 'list') {
            el.start = p.start || 1;
            el.style.listStyleType =
                { none: 'none', bullet: 'disc', number: 'decimal' }[p.marker] ||
                p.marker ||
                'decimal';
            if (p.connector) el.classList.add('connected-list');
            if (p.maxMarkerSize) el.style.setProperty('--marker-size', size(p.maxMarkerSize));
        }
        if (type === 'list-item') {
            if (p.icon)
                el.append(
                    node(
                        h('icon', { name: p.icon, color: p.iconColor || 'secondary', size: 24 }),
                        `${path}.icon`,
                    ),
                );
            if (p.disabled) el.style.opacity = '.5';
            if (p.marker) {
                const marker = document.createElement('span');
                marker.textContent = p.marker;
                marker.style.fontSize = size(p.markerSize || 'md');
                el.append(marker);
            }
            if (p.label) {
                const strong = document.createElement('strong');
                strong.textContent = p.label;
                el.append(strong);
            }
            if (p.description) {
                const d = document.createElement('p');
                d.textContent = p.description;
                el.append(d);
            }
        }
        if (type === 'carousel') {
            el.style.scrollSnapType = p.snap === false ? 'none' : 'x mandatory';
            el.style.setProperty('--visible-items', p.visibleItems || 1);
            listen(el, 'scroll', (e) => {
                clearTimeout(el._timer);
                el._timer = setTimeout(
                    () =>
                        action(
                            p.onChange,
                            Math.round(el.scrollLeft / (el.firstElementChild?.clientWidth || 1)),
                            e,
                        ),
                    100,
                );
            });
            setTimeout(() => {
                if (p.activeIndex && el.children[p.activeIndex])
                    el.scrollLeft = el.children[p.activeIndex].offsetLeft;
            }, 0);
        }
        if (type === 'carousel-item' || type === 'carousel-media-item') {
            el.style.scrollSnapAlign = p.snapAlign || 'start';
            if (type === 'carousel-media-item' && p.media)
                el.append(
                    node(
                        typeof p.media === 'string' ? h('AsyncImage', { src: p.media }) : p.media,
                        `${path}.media`,
                    ),
                );
        }
        if (type === 'popover') {
            el = document.createElement('details');
            el.className = 'genui-popover';
            el.open = Object.hasOwn(state, `@popover:${path}`)
                ? !!state[`@popover:${path}`]
                : !!p.open;
            listen(el, 'toggle', () => {
                state[`@popover:${path}`] = el.open;
                action(p.onOpenChange, el.open, null);
                bridge({ type: 'state', state: getSnapshot() });
                reportLayout();
            });
            if (p.showOnHover) {
                listen(el, 'mouseenter', () => {
                    el._hover = setTimeout(() => {
                        el.open = true;
                    }, p.hoverOpenDelay || 0);
                });
                listen(el, 'mouseleave', () => {
                    clearTimeout(el._hover);
                    el.open = false;
                });
            }
        }
        if (type === 'popover-trigger') {
            const summary = document.createElement('summary');
            listen(summary, 'click', (e) => action(p.onClick, null, e));
            el = summary;
        }
        if (type === 'popover-content') {
            el.dataset.side = p.side || 'bottom';
            if (p.align) el.style.textAlign = p.align;
            el.style.marginTop = size(p.sideOffset ?? 8);
            el.style.position = 'absolute';
            el.style.zIndex = '10';
            el.style.width = p.width ? size(p.width) : 'max-content';
            el.style.maxWidth = 'min(320px, 100vw - 16px)';
            if (p.align === 'end') el.style.right = '0';
            else el.style.left = '0';
            if (p.side === 'top') {
                el.style.bottom = '100%';
                el.style.marginBottom = size(p.sideOffset ?? 8);
            }
            if (p.showCloseButton) {
                const close = document.createElement('button');
                close.textContent = '×';
                close.setAttribute('aria-label', 'Close');
                listen(close, 'click', () => {
                    const details = el.closest('details');
                    if (details) details.open = false;
                });
                el.append(close);
            }
        }
        children.forEach((c, i) => {
            const child = node(c, `${path}.${c?.props?.key ?? i}`);
            if (['button', 'pressable'].includes(type) && c?.type === 'icon')
                child.setAttribute('aria-hidden', 'true');
            el.append(child);
        });
        if (['text', 'title', 'caption', 'label'].includes(type) &&
            children.every(child => typeof child !== 'object') && /\$|\\\(|\\\[/.test(el.textContent))
            markMath(el, el.textContent);
        if (type === 'carousel' && p.showArrows) {
            const wrap = document.createElement('div'),
                controls = document.createElement('div');
            controls.className = 'genui-carousel-controls';
            [-1, 1].forEach((direction) => {
                const b = document.createElement('button');
                b.textContent = direction < 0 ? '‹' : '›';
                b.setAttribute('aria-label', direction < 0 ? 'Previous slide' : 'Next slide');
                listen(b, 'click', (e) => {
                    el.scrollBy({
                        left: direction * (el.firstElementChild?.clientWidth || el.clientWidth),
                        behavior: 'smooth',
                    });
                    action(
                        p.onChange,
                        Math.max(
                            0,
                            Math.round(el.scrollLeft / (el.firstElementChild?.clientWidth || 1)) +
                                direction,
                        ),
                        e,
                    );
                });
                controls.append(b);
            });
            wrap.append(el, controls);
            return wrap;
        }
        if (type === 'table') {
            const scroll = document.createElement('div');
            scroll.className = 'genui-table-scroll';
            scroll.setAttribute('role', 'region');
            scroll.setAttribute('aria-label', p.ariaLabel || 'Table');
            scroll.tabIndex = 0;
            scroll.append(el);
            return scroll;
        }
        return el;
    }
    function normalizeChart(content) {
        const input = typeof content === 'string' ? JSON.parse(content) : content;
        if (!input || typeof input !== 'object') throw Error('No chart configuration');
        if (input.chartType) return input;
        // Explicit Recharts-style nodes, observed as the source's chart language.
        const kinds = {
            BarChart: 'bar',
            LineChart: 'line',
            ScatterChart: 'scatter',
            PieChart: 'pie',
        };
        const kind = kinds[input.type];
        if (!kind) throw Error('Unsupported chart type');
        const children = input.children || [],
            props = input.props || {};
        const find = (type) => children.find((child) => child.type === type)?.props || {};
        const series = children
            .filter((child) => ['Bar', 'Line', 'Scatter'].includes(child.type))
            .map((child) => ({
                dataKey: child.props?.dataKey,
                label: child.props?.name || child.props?.dataKey,
                color: child.props?.stroke || child.props?.fill,
            }));
        const pie = find('Pie'),
            x = find('XAxis'),
            y = find('YAxis');
        return {
            ...props,
            chartType: kind,
            data: props.data || pie.data,
            xKey: x.dataKey,
            nameKey: pie.nameKey,
            valueKey: pie.dataKey,
            series,
            showXAxis: children.some((child) => child.type === 'XAxis'),
            showYAxis: children.some((child) => child.type === 'YAxis'),
            showGrid: children.some((child) => child.type === 'CartesianGrid'),
            showLegend: children.some((child) => child.type === 'Legend'),
            xAxisLabel: x.label,
            yAxisLabel: y.label,
        };
    }
    function chart(content, el, options = {}) {
        let c;
        try {
            c = {
                ...normalizeChart(content),
                ...Object.fromEntries(
                    Object.entries(options).filter(([key]) => key.startsWith('show')),
                ),
            };
        } catch (error) {
            return missing(el, options.alt || `Chart unavailable: ${error.message}`);
        }
        const fail = (reason) =>
            missing(el, options.alt || c.alt || `Chart unavailable: ${reason}`);
        if (!['bar', 'line', 'area', 'scatter', 'pie'].includes(c.chartType))
            return fail('unsupported chart type');
        if (!Array.isArray(c.data) || !c.data.length) return fail('no chart data');
        const numeric = (value) =>
            typeof value === 'number' && Number.isFinite(value)
                ? value
                : typeof value === 'string' && value.trim() !== '' && Number.isFinite(Number(value))
                  ? Number(value)
                  : null;
        const series = c.series?.length
            ? c.series
            : [{ dataKey: c.valueKey || 'value', label: c.valueKey || 'Value' }];
        if (series.some((s) => !s.dataKey)) return fail('series requires dataKey');
        const rows = c.data.map((row) => series.map((s) => numeric(row[s.dataKey])));
        if (!rows.some((row) => row.some((value) => value !== null)))
            return fail('no numeric values');
        const colors = series.map(
            (s, index) => color(s.color) || `var(--chart-${(index % 6) + 1})`,
        );
        const format = (value, s = series[0]) =>
            value === null
                ? '—'
                : `${s.valuePrefix || ''}${s.valueFormat === 'percent' ? (value * 100).toLocaleString(undefined, { maximumFractionDigits: 1 }) + '%' : value.toLocaleString(undefined, { maximumFractionDigits: s.valueFormat === 'integer' ? 0 : 2 })}${s.valueSuffix || c.valueSuffix || ''}`;
        const width =
                Number(options.size || c.size) ||
                chartWidths.get(el.dataset.nodePath) ||
                Math.max(100, Math.min(760, (global.innerWidth || 390) - 32)),
            height = Number(options.size || c.size || options.height || c.height) || 240;
        if (options.size || c.size) {
            el.style.width = size(options.size || c.size);
            el.style.maxWidth = '100%';
        }
        if (global.DOMParser && global.prompt) {
            const viewModel = {
                ...c,
                theme: renderTheme,
                series: series.map((s) => ({ ...s, type: s.type || c.chartType })),
                xAxis: c.xAxis || c.nameKey || c.xKey || 'x',
            };
            const response = JSON.parse(
                global.prompt(
                    '__genuiChart:' +
                        JSON.stringify({ operation: 'chart', viewModel, width, height }),
                ) || '{}',
            );
            if (response.error) return fail(response.error);
            if (response.svg) {
                const parsed = new global.DOMParser().parseFromString(
                    response.svg,
                    'image/svg+xml',
                );
                if (parsed.querySelector('parsererror'))
                    return fail('Original SVG renderer returned invalid XML');
                const svg = document.importNode(parsed.documentElement, true);
                svg.setAttribute('role', 'img');
                svg.setAttribute('aria-label', c.title || `${c.chartType} chart`);
                el.append(svg);
                listen(svg, 'pointermove', (event) => {
                    const bounds = svg.getBoundingClientRect(),
                        fraction = (event.clientX - bounds.left) / bounds.width;
                    const index = Math.max(
                        0,
                        Math.min(c.data.length - 1, Math.round(fraction * (c.data.length - 1))),
                    );
                    action(options.onHover, { index, data: c.data[index] }, event);
                });
                listen(svg, 'pointerleave', (event) =>
                    action(options.onHover, { index: null, data: null }, event),
                );
                effects.push(() => {
                    const actual = el.getBoundingClientRect().width,
                        key = el.dataset.nodePath;
                    if (actual > 0 && Math.abs((chartWidths.get(key) || width) - actual) > 1) {
                        chartWidths.set(key, actual);
                        queueRender();
                    }
                });
                return el;
            }
        }
        if (options.size || c.size) {
            el.style.width = size(options.size || c.size);
            el.style.maxWidth = '100%';
        }
        const svg = document.createElementNS(SVG_NS, 'svg');
        svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
        svg.setAttribute('role', 'img');
        svg.setAttribute('aria-label', c.title || c.axisLabel || `${c.chartType} chart`);
        el.append(svg);
        const add = (tag, attrs, text) => {
            const item = document.createElementNS(SVG_NS, tag);
            Object.entries(attrs).forEach(([key, value]) => item.setAttribute(key, String(value)));
            if (text != null) item.textContent = String(text);
            svg.append(item);
            return item;
        };
        const detail = document.createElement('div');
        detail.className = 'genui-chart-detail';
        detail.setAttribute('aria-live', 'polite');
        const legend = document.createElement('div');
        legend.className = 'genui-chart-legend';
        const legendItem = (label, color) => {
            const item = document.createElement('span'),
                swatch = document.createElement('i');
            swatch.className = 'genui-chart-swatch';
            swatch.style.background = color;
            item.append(swatch, document.createTextNode(label));
            legend.append(item);
        };
        const interactive = (mark, text) => {
            const title = document.createElementNS(SVG_NS, 'title');
            title.textContent = text;
            mark.append(title);
            mark.setAttribute('tabindex', '0');
            mark.setAttribute('aria-label', text);
            ['pointerenter', 'focus', 'click'].forEach((event) =>
                listen(mark, event, () => {
                    detail.textContent = text;
                }),
            );
        };
        if (c.chartType === 'pie') {
            const values = c.data.map((row) => numeric(row[c.valueKey || series[0].dataKey]));
            if (values.some((value) => value === null || value < 0))
                return fail('pie values must be finite and nonnegative');
            const total = values.reduce((sum, value) => sum + value, 0);
            if (!Number.isFinite(total) || total <= 0)
                return fail('pie total must be finite and positive');
            const cx = width / 2,
                cy = height / 2,
                radius = Math.min(width, height) / 2 - 16;
            const inner =
                typeof c.innerRadius === 'string' && c.innerRadius.endsWith('%')
                    ? (radius * parseFloat(c.innerRadius)) / 100
                    : Number(c.innerRadius) || 0;
            let angle = (Number(c.startAngle ?? -90) * Math.PI) / 180;
            values.forEach((value, index) => {
                const label = String(c.data[index][c.nameKey || 'name'] ?? index + 1),
                    pieColor =
                        color(c.data[index].fill || c.data[index].color) ||
                        `var(--chart-${(index % 6) + 1})`;
                const next = angle + (value / total) * Math.PI * 2;
                if (value > 0) {
                    const mark =
                        value === total
                            ? add('circle', {
                                  cx,
                                  cy,
                                  r: inner ? (radius + inner) / 2 : radius,
                                  fill: inner ? 'none' : pieColor,
                                  stroke: inner ? pieColor : 'none',
                                  'stroke-width': inner ? radius - inner : 0,
                              })
                            : add('path', {
                                  d: inner
                                      ? `M${cx + radius * Math.cos(angle)} ${cy + radius * Math.sin(angle)} A${radius} ${radius} 0 ${next - angle > Math.PI ? 1 : 0} 1 ${cx + radius * Math.cos(next)} ${cy + radius * Math.sin(next)} L${cx + inner * Math.cos(next)} ${cy + inner * Math.sin(next)} A${inner} ${inner} 0 ${next - angle > Math.PI ? 1 : 0} 0 ${cx + inner * Math.cos(angle)} ${cy + inner * Math.sin(angle)} Z`
                                      : `M${cx} ${cy} L${cx + radius * Math.cos(angle)} ${cy + radius * Math.sin(angle)} A${radius} ${radius} 0 ${next - angle > Math.PI ? 1 : 0} 1 ${cx + radius * Math.cos(next)} ${cy + radius * Math.sin(next)} Z`,
                                  fill: pieColor,
                                  stroke: color(c.data[index].stroke) || 'var(--surface)',
                                  'stroke-width': 2,
                              });
                    interactive(
                        mark,
                        `${label}: ${format(value)} (${((value / total) * 100).toFixed(1)}%)`,
                    );
                }
                if (c.showLegend !== false) legendItem(`${label} · ${format(value)}`, pieColor);
                angle = next;
            });
        } else {
            const nums = rows.flat().filter((value) => value !== null);
            const min = c.yAxisMin ?? Math.min(0, ...nums),
                max = c.yAxisMax ?? Math.max(...nums, 1),
                range = max - min;
            if (
                !Number.isFinite(min) ||
                !Number.isFinite(max) ||
                range <= 0 ||
                !Number.isFinite(range)
            )
                return fail('invalid axis range');
            const tickLabels = Array.from({ length: 5 }, (_, i) => format(min + (i * range) / 4));
            const left =
                    c.showYAxis === false
                        ? 12
                        : Math.min(
                              width * 0.36,
                              12 +
                                  Math.max(...tickLabels.map((label) => Array.from(label).length)) *
                                      7,
                          ),
                right = width - 12,
                top = 12,
                bottom = height - 36;
            const y = (value) => bottom - ((value - min) / range) * (bottom - top);
            const xs = c.data.map((row) => numeric(row[c.xKey || 'x']));
            if (c.chartType === 'scatter' && xs.some((value) => value === null))
                return fail('scatter requires numeric x values');
            const scatterMin = Math.min(...xs.filter((value) => value !== null)),
                scatterMax = Math.max(...xs.filter((value) => value !== null));
            const x = (index) =>
                c.chartType === 'scatter'
                    ? left +
                      ((xs[index] - scatterMin) / (scatterMax - scatterMin || 1)) * (right - left)
                    : left + ((index + 0.5) / c.data.length) * (right - left);
            listen(svg, 'pointermove', (event) => {
                const frame = svg.getBoundingClientRect();
                const position = ((event.clientX - frame.left) * width) / frame.width;
                let index = 0;
                for (let i = 1; i < c.data.length; i++)
                    if (Math.abs(x(i) - position) < Math.abs(x(index) - position)) index = i;
                action(options.onHover, { index, data: c.data[index] }, event);
            });
            listen(svg, 'pointerleave', (event) =>
                action(options.onHover, { index: null, data: null }, event),
            );
            for (let tick = 0; tick <= 4; tick++) {
                const value = min + (tick * range) / 4;
                if (c.showGrid !== false)
                    add('line', {
                        x1: left,
                        y1: y(value),
                        x2: right,
                        y2: y(value),
                        stroke: 'var(--border)',
                        'stroke-dasharray': '3 4',
                    });
                if (c.showYAxis !== false)
                    add(
                        'text',
                        {
                            x: left - 8,
                            y: y(value) + 4,
                            'text-anchor': 'end',
                            'font-size': 11,
                            fill: 'var(--tertiary)',
                        },
                        format(value),
                    );
            }
            if (c.showXAxis !== false) {
                const stride = Math.max(
                    1,
                    Math.ceil(c.data.length / Math.max(2, Math.floor(width / 60))),
                );
                c.data.forEach((row, index) => {
                    if (index % stride === 0 || index === c.data.length - 1)
                        add(
                            'text',
                            {
                                x: x(index),
                                y: height - 14,
                                'text-anchor': 'middle',
                                'font-size': 11,
                                fill: 'var(--tertiary)',
                            },
                            String(row[c.xKey || 'x'] ?? index + 1).slice(0, 14),
                        );
                });
            }
            const zero = y(Math.max(min, Math.min(max, 0)));
            series.forEach((s, seriesIndex) => {
                const color = colors[seriesIndex];
                // Missing samples break line segments instead of joining unrelated points.
                if (['line', 'area'].includes(s.type || c.chartType)) {
                    let segment = [];
                    const draw = () => {
                        if (segment.length && (s.type || c.chartType) === 'area')
                            add('polygon', {
                                points: `${segment[0].split(',')[0]},${zero} ${segment.join(' ')} ${segment[segment.length - 1].split(',')[0]},${zero}`,
                                fill: color,
                                'fill-opacity': s.fillOpacity ?? 0.15,
                            });
                        if (segment.length)
                            add('polyline', {
                                points: segment.join(' '),
                                fill: 'none',
                                stroke: color,
                                'stroke-width': 2.5,
                                'stroke-linejoin': 'round',
                                'stroke-linecap': 'round',
                            });
                        segment = [];
                    };
                    rows.forEach((row, index) => {
                        if (row[seriesIndex] === null) draw();
                        else segment.push(`${x(index)},${y(row[seriesIndex])}`);
                    });
                    draw();
                }
                rows.forEach((row, index) => {
                    const value = row[seriesIndex];
                    if (value === null) return;
                    let mark;
                    if ((s.type || c.chartType) === 'bar') {
                        const groupWidth = ((right - left) / c.data.length) * 0.72,
                            barWidth = groupWidth / series.length;
                        mark = add('rect', {
                            x: x(index) - groupWidth / 2 + seriesIndex * barWidth,
                            y: Math.min(y(value), zero),
                            width: Math.max(1, barWidth - 2),
                            height: Math.abs(y(value) - zero),
                            fill: color,
                            rx: 3,
                        });
                    } else if (c.chartType === 'scatter' || c.showPoints !== false) {
                        mark = add('circle', {
                            cx: x(index),
                            cy: y(value),
                            r: 3.5,
                            fill: color,
                            stroke: 'var(--surface)',
                            'stroke-width': 1.5,
                        });
                    }
                    if (mark)
                        interactive(
                            mark,
                            `${c.data[index][c.xKey || 'x'] ?? index + 1} · ${s.label || s.dataKey}: ${format(value, s)}`,
                        );
                    if (c.showValues)
                        add(
                            'text',
                            {
                                x: x(index),
                                y: y(value) - 8,
                                'text-anchor': 'middle',
                                'font-size': 10,
                                fill: color,
                            },
                            format(value, s),
                        );
                });
                if (c.showLegend !== false) legendItem(s.label || s.dataKey, color);
            });
        }
        if (c.showLegend !== false) el.append(legend);
        el.append(detail);
        // Always offer the actual data, including missing samples, to assistive readers.
        const data = document.createElement('details'),
            summary = document.createElement('summary'),
            table = document.createElement('table');
        data.className = 'genui-chart-data';
        summary.textContent =
            c.dataLabel || (global.__GENUI_LOCALE__ === 'ja' ? 'データを見る' : 'View data');
        table.className = 'genui-table';
        const header = document.createElement('tr');
        [
            c.xAxisLabel || c.nameKey || c.xKey || 'Label',
            ...(c.chartType === 'pie'
                ? [series[0].label || 'Value']
                : series.map((s) => s.label || s.dataKey)),
        ].forEach((label) => {
            const cell = document.createElement('th');
            cell.textContent = label;
            header.append(cell);
        });
        table.append(header);
        c.data.forEach((row, index) => {
            const tr = document.createElement('tr');
            const label = document.createElement('th');
            label.textContent = String(
                row[c.chartType === 'pie' ? c.nameKey || 'name' : c.xKey || 'x'] ?? index + 1,
            );
            tr.append(label);
            (c.chartType === 'pie'
                ? [numeric(row[c.valueKey || series[0].dataKey])]
                : rows[index]
            ).forEach((value, i) => {
                const cell = document.createElement('td');
                cell.textContent = format(value, series[i] || series[0]);
                tr.append(cell);
            });
            table.append(tr);
        });
        data.append(summary, table);
        el.append(data);
        return el;
    }

    function render() {
        const root =
            document.getElementById('genui-root') ||
            document.getElementById('root') ||
            document.body;
        const active = document.activeElement,
            selection =
                active && 'selectionStart' in active
                    ? [active.selectionStart, active.selectionEnd]
                    : null,
            focusID = active?.dataset?.focusPath;
        maps.length = 0;
        videos.length = 0;
        usedHooks.clear();
        renderScope = state;
        renderTheme = global.__GENUI_THEME__ || 'light';
        try {
            current = 'root';
            hookIndex = 0;
            stateSlotIndex = 0;
            stateSlots.length = 0;
            codeOutput = undefined;
            const ui = codeRender
                ? codeRender(DIL, GenUI, state, config.resources || {})
                : config.ui;
            const content = node(ui || codeOutput || h('text', {}, 'No UI content'));
            const fragment = document.createDocumentFragment();
            fragment.append(content);
            reconcileChildren(root, fragment);
            current = null;
            root.querySelectorAll('input,textarea,select').forEach((e, i) => {
                e.dataset.focusPath = e.dataset.nodePath || String(i);
            });
            if (focusID != null) {
                const e = Array.from(root.querySelectorAll('input,textarea,select')).find(
                    (element) => element.dataset.focusPath === focusID,
                );
                if (e && e !== document.activeElement) e.focus();
                if (selection)
                    try {
                        e.setSelectionRange(...selection);
                    } catch (_) {}
            }
            hooks.forEach((list, key) => {
                if (!usedHooks.has(key)) {
                    list.forEach((s) => s.cleanup?.());
                    hooks.delete(key);
                }
            });
            effects.splice(0).forEach((fn) => fn());
            typesetPendingMath();
            bridge({ type: 'state', state: getSnapshot() });
            reportLayout();
        } catch (e) {
            current = null;
            bridge({ type: 'error', message: String(e.message) });
            root.replaceChildren(
                missing(document.createElement('div'), `GenUI error: ${e.message}`),
            );
            reportLayout();
        }
    }
    function reportLayout() {
        requestAnimationFrame(() => {
            bridge({
                type: 'height',
                height: Math.ceil(
                    Math.max(
                        1,
                        document.body.getBoundingClientRect().height,
                        ...Array.from(
                            document.querySelectorAll?.(
                                '.genui-popover[open] .genui-popover-content',
                            ) || [],
                        ).map(
                            (element) =>
                                element.getBoundingClientRect().bottom + global.scrollY + 8,
                        ),
                    ),
                ),
            });
            bridge({
                type: 'videos',
                videos: videos.map((video) => ({
                    id: video.id,
                    videoId: video.videoId,
                    title: video.title,
                    poster: video.poster,
                    frame: {
                        x: video.el.getBoundingClientRect().x + (global.scrollX || 0),
                        y: video.el.getBoundingClientRect().y + (global.scrollY || 0),
                        width: video.el.getBoundingClientRect().width,
                        height: video.el.getBoundingClientRect().height,
                    },
                })),
            });
            bridge({
                type: 'maps',
                maps: maps.map((map) => {
                    const r = map.el.getBoundingClientRect(),
                        x = r.x + (global.scrollX || 0),
                        y = r.y + (global.scrollY || 0);
                    let left = r.x,
                        top = r.y,
                        right = r.x + r.width,
                        bottom = r.y + r.height;
                    for (
                        let ancestor = map.el.parentElement;
                        ancestor && ancestor !== document.body;
                        ancestor = ancestor.parentElement
                    ) {
                        const s = global.getComputedStyle?.(ancestor);
                        if (s && ['auto', 'scroll', 'hidden', 'clip'].includes(s.overflowX)) {
                            const a = ancestor.getBoundingClientRect();
                            left = Math.max(left, a.x);
                            right = Math.min(right, a.x + a.width);
                        }
                        if (s && ['auto', 'scroll', 'hidden', 'clip'].includes(s.overflowY)) {
                            const a = ancestor.getBoundingClientRect();
                            top = Math.max(top, a.y);
                            bottom = Math.min(bottom, a.y + a.height);
                        }
                    }
                    return {
                        id: map.id,
                        props: clone(map.props),
                        frame: { x, y, width: r.width, height: r.height },
                        clip: {
                            x: left + (global.scrollX || 0),
                            y: top + (global.scrollY || 0),
                            width: Math.max(0, right - left),
                            height: Math.max(0, bottom - top),
                        },
                    };
                }),
            });
        });
    }
    document.addEventListener('scroll', reportLayout, true);
    document.addEventListener('toggle', reportLayout, true);
    global.GenUIRuntime = {
        getSnapshot,
        videoEvent(id, type, value) {
            const video = videos.find((video) => video.id === id);
            if (!video) return;
            if (type === 'error') action(video.props.onPlayerError, value, null);
            if (type === 'state' && value === 1) action(video.props.onPlay, null, null);
        },
        updateDocument(next) {
            const compiled = next.code
                ? new Function('DIL', 'GenUI', 'state', 'resources', next.code)
                : null;
            for (const [key, value] of Object.entries(next.state || {})) {
                if (
                    !Object.hasOwn(state, key) ||
                    JSON.stringify(state[key]) === JSON.stringify(config.state?.[key])
                )
                    state[key] = clone(value);
            }
            for (const key of Object.keys(config))
                if (!Object.hasOwn(next, key)) delete config[key];
            Object.assign(config, clone(next));
            codeRender = compiled;
            queueRender();
        },
        applyPatch(operations) {
            if (config.code) throw Error('Patches require a declarative document');
            const next = applyJSONPatch(config, operations);
            if (!next.ui || next.code) throw Error('Patch must retain a declarative document');
            Object.keys(config).forEach((key) => delete config[key]);
            Object.assign(config, next);
            queueRender();
        },
        reset() {
            state = clone(config.state);
            saved.hooks = [];
            saved.hookSlots = {};
            hooks.forEach((list) => list.forEach((s) => s.cleanup?.()));
            hooks.clear();
            stateSlots.length = 0;
            queueRender();
        },
        setTheme(theme) {
            global.__GENUI_THEME__ = theme;
            document.documentElement.dataset.theme = theme;
            queueRender();
        },
    };
    global.__GENUI_RENDER__ = render;
    global.__GENUI_SET_THEME__ = (theme) => {
        global.__GENUI_THEME__ = theme;
        document.documentElement.dataset.theme = theme;
        queueRender();
    };
    document.documentElement.dataset.theme = global.__GENUI_THEME__ || 'light';
    global.addEventListener('resize', queueRender);
    global.addEventListener('pagehide', () =>
        hooks.forEach((list) => list.forEach((s) => s.cleanup?.())),
    );
    if (document.readyState === 'loading')
        document.addEventListener('DOMContentLoaded', () => {
            render();
            new ResizeObserver(reportLayout).observe(document.body);
        });
    else {
        render();
        new ResizeObserver(reportLayout).observe(document.body);
    }
})(typeof window === 'undefined' ? globalThis : window);
