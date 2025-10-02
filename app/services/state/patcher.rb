module State
  class Patcher
    def initialize(redis)
      @r = redis
    end

    def patch!(key:, expected_version:, patch:, ttl_seconds: 86_400)
      @r.watch(key) do
        current = JSON.parse(@r.get(key) || "{}")
        cur_v   = current["version"] || 0
        raise "Version conflict" unless cur_v == expected_version

        merged = deep_merge(current, patch)
        merged["version"] = expected_version + 1

        @r.multi do |m|
          m.set(key, merged.to_json)
          m.expire(key, ttl_seconds)
        end
      end
      true
    rescue Redis::BaseError, RuntimeError
      false
    ensure
      @r.unwatch
    end

    private

    def deep_merge(a, b)
      a.merge(b) do |_, av, bv|
        if av.is_a?(Hash) && bv.is_a?(Hash)
          deep_merge(av, bv)
        else
          bv # arrays/scalars replace (simple MVP policy)
        end
      end
    end
  end
end
