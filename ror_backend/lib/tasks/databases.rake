require 'alias_task_chain'

namespace :db do

    alias_task_chain :charset => :environment do
      config = ActiveRecord::Base.configurations[RAILS_ENV || 'development']
      case config['adapter']
      when 'sqlserver'
        ActiveRecord::Base.establish_connection(config)
        puts ActiveRecord::Base.connection.charset
      else
        Rake::Task["db:charset:original"].execute
      end
    end

    namespace :schema do

      alias_task_chain :load => :environment do
        if ActiveRecord::Base.configurations[RAILS_ENV]["adapter"] == "sqlserver"
          puts 'Task db:schema:load skipped for SQL Server.'
        else
          Rake::Task["db:schema:load:original"].execute
        end
      end

    end

    namespace :structure do

      alias_task_chain :dump => :environment do
        if ActiveRecord::Base.configurations[RAILS_ENV]["adapter"] == "sqlserver"
          Rake::Task["db:myproject:structure:dump"].execute
        else
          Rake::Task["db:structure:dump:original"].execute
        end
      end

    end

    namespace :test do

      desc "Force recreate the test databases from the development structure"
      task :clone_force => :environment do
        force_test_database_needs_migrations { Rake::Task["db:test:clone"].execute }
      end

      alias_task_chain :clone => :environment do
        if ActiveRecord::Base.configurations[RAILS_ENV]["adapter"] == "sqlserver"
          Rake::Task["db:myproject:structure:dump"].execute
          Rake::Task["db:myproject:test:clone_structure"].execute
        else
          Rake::Task["db:test:clone:original"].execute
        end
      end

      alias_task_chain :clone_structure => "db:structure:dump" do
        if ActiveRecord::Base.configurations[RAILS_ENV]["adapter"] == "sqlserver"
          Rake::Task["db:myproject:test:clone_structure"].execute
        else
          Rake::Task["db:test:clone_structure:original"].execute
        end
      end

      alias_task_chain :purge => :environment do
        if ActiveRecord::Base.configurations[RAILS_ENV]["adapter"] == "sqlserver"
          puts 'Task db:test:purge skipped for SQL Server.'
        else
          Rake::Task["db:test:purge:original"].execute
        end
      end

    end

    namespace :myproject do

      namespace :structure do

        task :setup_remote_dirs => :environment do
          with_db_server_connection do |ssh|
            ssh.exec! "rm -rf #{structure_dirs}"
            ssh.exec! "mkdir -p #{structure_dirs}"
          end
        end

        task :dump => [:environment, :setup_remote_dirs] do
          with_db_server_connection do |ssh|
            puts "-- Dropping and/or creating a new #{database_name(:test => true)} DB..."
            ssh.exec! "osql -E -S #{osql_scptxfr_host} -d master -Q 'DROP DATABASE #{database_name(:test => true)}'"
            ssh.exec! "osql -E -S #{osql_scptxfr_host} -d master -Q 'CREATE DATABASE #{database_name(:test => true)}'"
            puts "-- Dumping #{database_name} structure from remote DB into remote #{structure_dirs} directory..."
            ssh.exec! "scptxfr /s #{osql_scptxfr_host} /d #{database_name} /I /f #{structure_filepath} /q /A /r"
            ssh.exec! "scptxfr /s #{osql_scptxfr_host} /d #{database_name} /I /F #{structure_dirs}/ /q /A /r"
            puts "-- Chainging all custom filegroups from #{structure_filepath} to PRIMARY default..."
            sed_command = "sed -r -e 's/ON \\[(#{my_db_filegroups.join('|')})\\]/ON [PRIMARY]/' -i #{structure_filepath}"
            ssh.exec!(sed_command)
            puts "-- Removing all TEXTIMAGE_ON filegroups from #{structure_filepath}..."
            sed_command = "sed -r -e 's/TEXTIMAGE_ON \\[PRIMARY\\]//' -i #{structure_filepath}"
            ssh.exec!(sed_command)
            puts "-- Changing all DB names to test DBs in #{structure_filepath}..."
            sed_command = "sed -r -e 's/#{database_name}/#{database_name(:test => true)}/g' -i #{structure_filepath}"
            ssh.exec!(sed_command)
          end if test_database_needs_migrations?
        end

      end

      namespace :test do

        task :clone_structure => :environment do
          @close_db_server_connection = true
          with_db_server_connection do |ssh|
            puts "-- Importing clean structure into #{database_name(:test => true)} DB..."
            dropfkscript = "#{database_host.upcase}.#{database_name}.DP1".gsub(/\\/,'-')
            ssh.exec! "osql -E -S #{osql_scptxfr_host} -d #{database_name(:test => true)} -i #{structure_dirs}/#{dropfkscript}"
            ssh.exec! "osql -E -S #{osql_scptxfr_host} -d #{database_name(:test => true)} -i #{structure_filepath}"
            puts "-- Removing foreign key constraints #{database_name(:test => true)}..."
            ssh.exec! "osql -E -S #{osql_scptxfr_host} -d #{database_name(:test => true)} -i #{structure_dirs}/#{dropfkscript}"
            copy_schema_migrations
          end if test_database_needs_migrations?
        end

      end

    end

  end




  def database_name(options={})
    suffix = options[:test] ? '_test' : ''
    "MyProjectDb#{suffix}"
  end

  def database_host
    ENV['MYPROJECT_DEVDB_HOST']
  end

  def database_user
    ENV['MYPROJECT_DEVDB_USER']
  end

  def with_db_server_connection
    require 'net/ssh' unless defined? Net::SSH
    @database_connection ||= Net::SSH.start(database_host, database_user, :verbose => :fatal)
    yield(@database_connection)
    @database_connection.close if @close_db_server_connection
  end

  def test_database_needs_migrations?
    return true if @force_test_database_needs_migrations
    return @test_database_needs_migrations unless @test_database_needs_migrations.nil?
    ActiveRecord::Base.establish_connection(:test)
    @test_database_needs_migrations = ActiveRecord::Migrator.new(:up,'db/migrate').pending_migrations.present?
  end

  def force_test_database_needs_migrations
    @force_test_database_needs_migrations = true
    yield
  ensure
    @force_test_database_needs_migrations = false
  end

  def osql_scptxfr_host
    'localhost'
  end

  def structure_filepath
    "#{structure_dirs}/#{RAILS_ENV}_structure.sql"
  end

  def structure_dirs
    "db/myproject"
  end

  def my_db_filegroups
    ['FOO_DATA','BAR_DATA']
  end

  def copy_schema_migrations
    schema_table = ActiveRecord::Migrator.schema_migrations_table_name
    ActiveRecord::Base.establish_connection(:development)
    versions = ActiveRecord::Base.connection.select_values("SELECT version FROM #{schema_table}").map(&:to_i).sort
    ActiveRecord::Base.establish_connection(:test)
    puts "-- Copying Schema Migrations..."
    versions.each do |version|
      ActiveRecord::Base.connection.insert("INSERT INTO #{schema_table} (version) VALUES ('#{version}')")
    end
  end 