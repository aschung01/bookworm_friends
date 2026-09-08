/* DOM stub from the design-mockups skill's reference/pitfalls.md, extended so
   keyboard handlers and the version list can be driven headlessly. */
const mk = () => ({
    _v: "",
    set innerHTML(v) {
        this._v = v;
    },
    get innerHTML() {
        return this._v;
    },
    textContent: "",
    hidden: false,
    value: "",
    placeholder: "",
    dataset: {},
    style: {},
    classList: {
        toggle() {},
        add() {},
        remove() {},
        contains() {
            return false;
        },
    },
    addEventListener() {},
    focus() {},
    blur() {},
    select() {},
    contains() {
        return false;
    },
    querySelectorAll() {
        return [];
    },
    querySelector() {
        return null;
    },
    closest() {
        return null;
    },
    getBoundingClientRect() {
        return { top: 0 };
    },
    scrollIntoView() {},
    nextElementSibling: null,
    tagName: "DIV",
});
const nodes = {};
global.document = {
    getElementById: (id) => (nodes[id] = nodes[id] || mk()),
    querySelectorAll: () => [],
    addEventListener() {},
    body: { scrollHeight: 1000 },
    activeElement: null,
};
global.window = {
    addEventListener() {},
    scrollTo() {},
    innerHeight: 800,
    scrollY: 0,
};
global.requestAnimationFrame = (f) => f();
global.Event = class {
    constructor(t) {
        this.type = t;
    }
};
