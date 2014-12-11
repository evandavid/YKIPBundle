class User < ActiveRecord::Base
    self.table_name_prefix = 'dbo.' 
end
