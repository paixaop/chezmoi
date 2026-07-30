function keyToString(key, modifier) {
    return `${modifier.join('+')}-${key}`.toUpperCase();
}