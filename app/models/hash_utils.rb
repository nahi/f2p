module HashUtils 
  def v(*keywords)
    keywords.inject(self) { |r, k|
      r[k] if r
    }
  end
end
