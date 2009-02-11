class Profile < ActiveRecord::Base
  validates_inclusion_of :font_size, :in => 4..30
  validates_inclusion_of :entries_in_page, :in => 5..100
  validates_inclusion_of :text_folding_size, :in => 10..65536
end
