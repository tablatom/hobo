module Hobo

  module Scopes

    module AutomaticScopes

      def create_automatic_scope(name)
        ScopeBuilder.new(self, name).create_scope
      rescue ActiveRecord::StatementInvalid => e
        # Problem with the database? Don't try to create automatic
        # scopes
        if ActiveRecord::Base.logger
          ActiveRecord::Base.logger.warn "!! Database exception during hobo auto-scope creation -- continuing automatic scopes"
          ActiveRecord::Base.logger.warn "!! #{e.to_s}"
        end
        false
      end

    end

    # The methods on this module add scopes to the given class
    class ScopeBuilder

      def initialize(klass, name)
        @klass = klass
        @name  = name.to_s
      end

      attr_reader :name

      def create_scope
        matched_scope = true


        # --- Association Queries --- #

        # with_players(player1, player2)
        if name =~ /^with_(.*)/ && (refl = reflection($1))

          def_scope do |*records|
            if records.empty?
              { :conditions => exists_sql_condition(refl, true) }
            else
              records = records.flatten.compact.map {|r| find_if_named(refl, r) }
              exists_sql = ([exists_sql_condition(refl)] * records.length).join(" AND ")
              { :conditions => [exists_sql] + records }
            end
          end

        # with_player(a_player)
        elsif name =~ /^with_(.*)/ && (refl = reflection($1.pluralize))

          exists_sql = exists_sql_condition(refl)
          def_scope do |record|
            record = find_if_named(refl, record)
            { :conditions => [exists_sql, record] }
          end

        # any_of_players(player1, player2)
        elsif name =~ /^any_of_(.*)/ && (refl = reflection($1))

          def_scope do |*records|
            if records.empty?
              { :conditions => exists_sql_condition(refl, true) }
            else
              records = records.flatten.compact.map {|r| find_if_named(refl, r) }
              exists_sql = ([exists_sql_condition(refl)] * records.length).join(" OR ")
              { :conditions => [exists_sql] + records }
            end
          end

        # without_players(player1, player2)
        elsif name =~ /^without_(.*)/ && (refl = reflection($1))

          def_scope do |*records|
            if records.empty? 
              { :conditions => "NOT (#{exists_sql_condition(refl, true)})" }
            else
              records = records.flatten.compact.map {|r| find_if_named(refl, r) }
              exists_sql = ([exists_sql_condition(refl)] * records.length).join(" AND ")
              { :conditions => ["NOT (#{exists_sql})"] + records }
            end
          end

        # without_player(a_player)
        elsif name =~ /^without_(.*)/ && (refl = reflection($1.pluralize))

          exists_sql = exists_sql_condition(refl)
          def_scope do |record|
            record = find_if_named(refl, record)
            { :conditions => ["NOT #{exists_sql}", record] }
          end

        # team_is(a_team)
        elsif name =~ /^(.*)_is$/ && (refl = reflection($1)) && refl.macro.in?([:has_one, :belongs_to])

          if refl.options[:polymorphic]
            def_scope do |record|
              record = find_if_named(refl, record)
              { :conditions => ["#{foreign_key_column refl} = ? AND #{$1}_type = ?", record, record.class.name] }
            end
          else
            def_scope do |record|
              record = find_if_named(refl, record)
              { :conditions => ["#{foreign_key_column refl} = ?", record] }
            end
          end

        # team_is_not(a_team)
        elsif name =~ /^(.*)_is_not$/ && (refl = reflection($1)) && refl.macro.in?([:has_one, :belongs_to])

          if refl.options[:polymorphic]
            def_scope do |record|
              record = find_if_named(refl, record)
              { :conditions => ["#{foreign_key_column refl} <> ? OR #{name}_type <> ?", record, record.class.name] }
            end
          else
            def_scope do |record|
              record = find_if_named(refl, record)
              { :conditions => ["#{foreign_key_column refl} <> ?", record] }
            end
          end


        # --- Column Queries --- #

        # name_is(str)
        elsif name =~ /^(.*)_is$/ && (col = column($1))

          def_scope do |str|
            { :conditions => ["#{column_sql(col)} = ?", str] }
          end

        # name_is_not(str)
        elsif name =~ /^(.*)_is_not$/ && (col = column($1))

          def_scope do |str|
            { :conditions => ["#{column_sql(col)} <> ?", str] }
          end

        # name_contains(str)
        elsif name =~ /^(.*)_contains$/ && (col = column($1))

          def_scope do |str|
            { :conditions => ["#{column_sql(col)} LIKE ?", "%#{str}%"] }
          end

        # name_does_not_contain
        elsif name =~ /^(.*)_does_not_contain$/ && (col = column($1))

          def_scope do |str|
            { :conditions => ["#{column_sql(col)} NOT LIKE ?", "%#{str}%"] }
          end

        # name_starts(str)
        elsif name =~ /^(.*)_starts$/ && (col = column($1))

          def_scope do |str|
            { :conditions => ["#{column_sql(col)} LIKE ?", "#{str}%"] }
          end

        # name_does_not_start
        elsif name =~ /^(.*)_does_not_start$/ && (col = column($1))

          def_scope do |str|
            { :conditions => ["#{column_sql(col)} NOT LIKE ?", "#{str}%"] }
          end

        # name_ends(str)
        elsif name =~ /^(.*)_ends$/ && (col = column($1))

          def_scope do |str|
            { :conditions => ["#{column_sql(col)} LIKE ?", "%#{str}"] }
          end

        # name_does_not_end(str)
        elsif name =~ /^(.*)_does_not_end$/ && (col = column($1))

          def_scope do |str|
            { :conditions => ["#{column_sql(col)} NOT LIKE ?", "%#{str}"] }
          end

        # published (a boolean column)
        elsif name =~ /^is_(.*)$/ && (col = column($1)) && (col.type == :boolean)

          def_scope :conditions => ["#{column_sql(col)} = ?", true]

        # not_published
        elsif name =~ /^not_(.*)$/ && (col = column($1)) && (col.type == :boolean)

          def_scope :conditions => ["#{column_sql(col)} <> ?", true]

        # published_before(time)
        elsif name =~ /^(.*)_before$/ && (col = column("#{$1}_at") || column("#{$1}_date") || column("#{$1}_on")) && col.type.in?([:date, :datetime, :time, :timestamp])

          def_scope do |time|
            { :conditions => ["#{column_sql(col)} < ?", time] }
          end

        # published_after(time)
        elsif name =~ /^(.*)_after$/ && (col = column("#{$1}_at") || column("#{$1}_date") || column("#{$1}_on")) && col.type.in?([:date, :datetime, :time, :timestamp])

          def_scope do |time|
            { :conditions => ["#{column_sql(col)} > ?", time] }
          end

        # published_between(time1, time2)
        elsif name =~ /^(.*)_between$/ && (col = column("#{$1}_at") || column("#{$1}_date") || column("#{$1}_on")) && col.type.in?([:date, :datetime, :time, :timestamp])

          def_scope do |time1, time2|
            { :conditions => ["#{column_sql(col)} >= ? AND #{column_sql(col)} <= ?", time1, time2] }
          end

         # active (a lifecycle state)
        elsif @klass.has_lifecycle? && name =~ /^state_is_(.*)$/ && $1.to_sym.in?(@klass::Lifecycle.state_names)

          if @klass::Lifecycle.state_names.length == 1
            # nothing to check for - create a dummy scope
            def_scope :conditions => ""
            true
          else
            def_scope :conditions => ["#{@klass.table_name}.#{@klass::Lifecycle.state_field} = ?", $1]
          end

        # self is / is not
        elsif name == "is"

          def_scope do |record|
            { :conditions => ["#{@klass.table_name}.#{@klass.primary_key} = ?", record] }
          end

        elsif name == "is_not"

          def_scope do |record|
            { :conditions => ["#{@klass.table_name}.#{@klass.primary_key} <> ?", record] }
          end

        else

          case name
            
          when "by_most_recent"
            def_scope :order => "#{@klass.table_name}.created_at DESC"

          when "recent"
            
            if "created_at".in?(@klass.columns.*.name)
              def_scope do |*args|
                count = args.first || 6
                { :limit => count, :order => "#{@klass.table_name}.created_at DESC" }
              end
            else
              def_scope do |*args|
                count = args.first || 6
                { :limit => count }
              end
            end
            
          when "limit"
            def_scope do |count|
              { :limit => count }
            end

          when "order_by"
            klass = @klass
            def_scope do |*args|
              field, asc = args
              type = klass.attr_type(field)
              if type.nil? #a virtual attribute from an SQL alias, e.g., 'total' from 'COUNT(*) AS total'
                # can also be has_many association, let's check it out
                _, assoc, count = *field._?.match(/^([a-z_]+)(?:\.([a-z_]+))?/)
                refl = klass.attr_type(assoc)

                if refl.respond_to?(:primary_key_name) && refl.macro == :has_many && (count._?.upcase == 'COUNT' || count._?.upcase == 'SIZE')
                  owner_primary_key = "#{klass.quoted_table_name}.#{klass.primary_key}"
                  # now we have :has_many association in refl, is this a through association?
                  if (through = refl.through_reflection) && (source = refl.source_reflection)
                    # has_many through association was found and now we have a few variants:
                    # 1) owner.has_many -> through.belongs_to <- source.has_many (many to many, source.macro == :belongs_to )
                    # 2) owner.has_many -> through.has_many -> source.belongs_to (many to one through table, source.macro == :has_many)
                    klass_assoc_name = klass.name.send(source.macro == :belongs_to ? :tableize : :underscore).to_sym
                    counter_cache_column = refl.klass.reflections[klass_assoc_name]._?.counter_cache_column
                    colspec = counter_cache_column || "(SELECT COUNT(*) AS count_all FROM #{refl.quoted_table_name} INNER JOIN #{through.quoted_table_name}" +
                      " ON #{source.quoted_table_name}.#{source.macro == :belongs_to ? source.klass.primary_key : through.association_foreign_key}" +
                      " = #{through.quoted_table_name}.#{source.macro == :belongs_to ? source.association_foreign_key : through.klass.primary_key}" +
                      " WHERE #{through.quoted_table_name}.#{through.primary_key_name} = #{owner_primary_key} )"
                  else
                    # simple many to one (has_many -> belongs_to) association
                    counter_cache_column = refl.klass.reflections[klass.name.underscore.to_sym]._?.counter_cache_column
                    colspec = counter_cache_column || "(SELECT COUNT(*) as count_all FROM #{refl.quoted_table_name}" +
                      " WHERE #{refl.quoted_table_name}.#{refl.primary_key_name} = #{owner_primary_key})"
                  end

                else
                  colspec = "#{field}" # don't prepend the table name
                end
              elsif type.respond_to?(:name_attribute) && (name = type.name_attribute)
                include = field
                colspec = "#{type.table_name}.#{name}"
              else
                colspec = "#{klass.table_name}.#{field}"
              end
              { :order => "#{colspec} #{asc._?.upcase}", :include => include }
            end


          when "include"
            def_scope do |inclusions|
              { :include => inclusions }
            end

          when "includes"
            def_scope do |inclusions|
              { :include => inclusions }
            end

          when "search"
            def_scope do |query, *fields|
              match_keyword = ::ActiveRecord::Base.connection.adapter_name == "PostgreSQL" ? "ILIKE" : "LIKE"

              words = query.split
              args = []
              word_queries = words.map do |word|
                field_query = '(' + fields.map { |field| "(#{@klass.table_name+'.' unless field.to_s.index('.')}#{field} #{match_keyword} ?)" }.join(" OR ") + ')'
                args += ["%#{word}%"] * fields.length
                field_query
              end

              { :conditions => [word_queries.join(" AND ")] + args }
            end

          else
            matched_scope = false
          end

        end
        matched_scope
      end


      def column_sql(column)
        "#{@klass.table_name}.#{column.name}"
      end


      def exists_sql_condition(reflection, any=false)
        owner = @klass
        owner_primary_key = "#{owner.table_name}.#{owner.primary_key}"
 
        if reflection.options[:through]
          join_table   = reflection.through_reflection.klass.table_name
          owner_fkey   = reflection.through_reflection.primary_key_name
          conditions   = reflection.options[:conditions].blank? ? '' : " AND #{reflection.through_reflection.klass.send(:sanitize_sql_for_conditions, reflection.options[:conditions])}"
 
          if any
            "EXISTS (SELECT * FROM #{join_table} WHERE #{join_table}.#{owner_fkey} = #{owner_primary_key}#{conditions})"
          else
            source_fkey  = reflection.source_reflection.primary_key_name
            "EXISTS (SELECT * FROM #{join_table} " +
              "WHERE #{join_table}.#{source_fkey} = ? AND #{join_table}.#{owner_fkey} = #{owner_primary_key}#{conditions})"
          end
        else
          foreign_key = reflection.primary_key_name
          related     = reflection.klass
          conditions = reflection.options[:conditions].blank? ? '' : " AND #{reflection.klass.send(:sanitize_sql_for_conditions, reflection.options[:conditions])}"
 
          if any
            "EXISTS (SELECT * FROM #{related.table_name} " +
              "WHERE #{related.table_name}.#{foreign_key} = #{owner_primary_key}#{conditions})"
          else
            "EXISTS (SELECT * FROM #{related.table_name} " +
              "WHERE #{related.table_name}.#{foreign_key} = #{owner_primary_key} AND " +
              "#{related.table_name}.#{related.primary_key} = ?#{conditions})"
          end
        end
      end

      def find_if_named(reflection, string_or_record)
        if string_or_record.is_a?(String)
          name = string_or_record
          reflection.klass.named(name)
        else
          string_or_record # a record
        end
      end


      def column(name)
        @klass.column(name)
      end


      def reflection(name)
        @klass.reflections[name.to_sym]
      end


      def def_scope(options={}, &block)
        _name = name.to_sym
        @klass.named_scope(_name, block || options)
        # this is tricky; ordinarily, we'd worry about subclasses that haven't yet been loaded.
        # HOWEVER, they will pick up the scope setting via read_inheritable_attribute when they do
        # load, so only the currently existing subclasses need to be fixed up.
        _scope = @klass.scopes[_name]
        @klass.send(:subclasses).each do |k|
          k.scopes[_name] = _scope
        end
      end


      def primary_key_column(refl)
        "#{refl.klass.table_name}.#{refl.klass.primary_key}"
      end


      def foreign_key_column(refl)
        "#{@klass.table_name}.#{refl.primary_key_name}"
      end

    end

  end

end
