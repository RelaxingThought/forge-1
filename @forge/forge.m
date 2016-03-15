classdef forge < handle
    properties
        people
        bills
        history
        rollcalls
        sponsors
        votes
        
        bill_set
        
        chamber_leadership_key % key for leadership codes
        committee_key
        committee_leadership_key % key for committee leadership
        
        state
        data_directory
        
        gif_directory
        histogram_directory
        
        senate_size
        house_size
    end
    
    properties (Constant)
        PARTY_KEY = containers.Map({'0','1','Democrat','Republican'},{'Democrat','Republican',0,1})
        VOTE_KEY  = containers.Map({'1','2','3','4','yea','nay','absent','no vote'},{'yea','nay','absent','no vote',1,2,3,4});
        
        ISSUE_KEY = containers.Map([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],{...
            'Agriculture',...
            'Commerce, Business, Economic Development',...
            'Courts & Judicial',...
            'Education',...
            'Elections & Apportionment',...
            'Employment & Labor',...
            'Environment & Natural Resources',...
            'Family, Children, Human Affairs & Public Health',...
            'Banks & Financial Institutions',...
            'Insurance',...
            'Government & Regulatory Reform',...
            'Local Government',...
            'Roads & Transportation',...
            'Utilities, Energy & Telecommunications',...
            'Ways & Means, Appropriations',...
            'Other'});
    end
    
    methods
        function obj = forge(recompute)
            obj.state = 'IN';
            obj.data_directory = 'data';
            
            obj.gif_directory = 'outputs/gif';
            obj.histogram_directory = 'outputs/histograms';
            
            obj.senate_size = 50;
            obj.house_size = 100;
            
            if recompute ||  exist('saved_data.mat','file') ~= 2
                
                bills_create     = obj.readAllFilesOfSubject('bills');
                people_create    = obj.readAllFilesOfSubject('people');
                rollcalls_create = obj.readAllFilesOfSubject('rollcalls');
                
                rollcalls_create.senate      = strncmpi(rollcalls_create{:,'description'},{'S'},1);
                rollcalls_create.total_vote  = rollcalls_create.yea + rollcalls_create.nay;
                rollcalls_create.yes_percent = rollcalls_create.yea ./ rollcalls_create.total_vote;
                
                sponsors_create = obj.readAllFilesOfSubject('sponsors');
                votes_create    = obj.readAllFilesOfSubject('votes');
                history_create  = obj.readAllFilesOfSubject('history');
                
                bill_set_create = containers.Map('KeyType','int32','ValueType','any');
                
                for i = 1:length(bills_create.bill_id)
                    
                    template = obj.getBillTemplate();
                    
                    template(end+1).bill_id = bills_create{i,'bill_id'}; %#ok<AGROW>
                    template.bill_number = bills_create{i,'bill_number'};
                    template.title = bills_create{i,'title'};
                    % template.issue_category = ??? learning algorithm
                    % which takes the title as input?
                    
                    template.sponsors = sponsors_create{sponsors_create.bill_id == bills_create{i,'bill_id'},'sponsor_id'};
                    
                    template.history = history_create(bills_create{i,'bill_id'} == history_create.bill_id,:);
                    % date introduced?
                    % date of last vote?
                    
                    bill_rollcalls = rollcalls_create(rollcalls_create.bill_id == bills_create{i,'bill_id'},:);
                    
                    % ------------------ House Data --------------------- %
                    house_rollcalls = bill_rollcalls(bill_rollcalls.senate == 0,:);
                    
                    if ~isempty(house_rollcalls)
                        
                        house_data = obj.processChamberRollcalls(house_rollcalls,votes_create,obj.house_size*0.6);
                        
                        template.house_data = house_data;
                        template.passed_house = (house_data.final_yes_percentage > 0.5);
                    end
                    
                    % ------------------ Senate Data -------------------- %
                    senate_rollcalls = bill_rollcalls(bill_rollcalls.senate == 0,:);
                    
                    if ~isempty(senate_rollcalls)
                        
                        senate_data = obj.processChamberRollcalls(senate_rollcalls,votes_create,obj.senate_size*0.6);
                        
                        template.senate_data = senate_data;
                        template.passed_senate = (senate_data.final_yes_percentage > 0.5);
                    end
                    
                    if ~isempty(template.passed_senate) && ~isempty(template.passed_house)
                        template.passed_both = (template.passed_senate && template.passed_house);
                    else
                        template.passed_both = 0;
                    end
                    % signed into law?
                    
                    bill_set_create(bills_create{i,'bill_id'}) = template;
                end
                clear chamber_votes committee_votes bill_history bill_rollcalls i j house_data house_rollcalls senate_data senate_rollcalls template
                
                var_list = who;
                var_list = var_list(~ismember(var_list,'obj'));
                save('processed_data',var_list{:})
            else
                load('processed_data') %
            end
            
            obj.bills     = bills_create;
            obj.history   = history_create;
            obj.people    = people_create;
            obj.rollcalls = rollcalls_create;
            obj.sponsors  = sponsors_create;
            obj.votes     = votes_create;
            
            obj.bill_set = bill_set_create;
        end
        
        function run(obj)
            
            
            % The goal is to create a container map, keyed by bill id
            bills = containers.Map('KeyType','int32','ValueType','struct');
            
            % each entry will be a structure that contains the important
            % information about the bill and its passage through both the
            % senate and the house
            % this might be an opportunity to bring in the as-yet
            % unused "history" sheet - from which it should be possible
            % to mine primary vs secondary sponsors
            
            % build in a key for each coded variable on both a bill and
            % person basis: {bill : issue, committee of origin } {person :
            % party, chamber leadership, committee leadership}
            
            % the result will be a system in which the bills are stored in
            % a struct that can be drilled to get specific information and
            % people will continue to be stored in a table
            
            % district information, which will be included soon, will also
            % be stored in table format
            
            % makes sense for the relational things (seat proximity, vote
            % similarity, sponsorship) to be stored in a table as well -
            % they can be referenced directly by the legislator ID
            
            % ID should probably be stored as a string throughout, that way
            % it can be used in variable names more easily
        end
        
        function output = readAllFilesOfSubject(obj,type)
            % initialize the full file list and output matrix
            directory = sprintf('%s/%s/legiscan',obj.data_directory,obj.state);
            list   = dir(directory);
            output = [];
            
            % loop over the available files
            for i = 1:length(list)
                % if the file fits the format we're looking for
                if ~isempty(regexp(list(i).name,'(\d+)-(\d+)_Regular_Session','once'))
                    if istable(output) % if the output file exists, append
                        output = [output;readtable(sprintf('%s/%s/csv/%s.csv',directory,list(i).name,type))]; %#ok<AGROW>
                    else % if it doesn't exist, create it
                        output = readtable(sprintf('%s/%s/csv/%s.csv',directory,list(i).name,type));
                    end
                end
            end
        end
        
        function vote_structure = addRollcallVotes(obj,new_rollcall,new_votelist)
            vote_structure.rollcall_id = new_rollcall.roll_call_id;
            vote_structure.description   = new_rollcall.description;
            vote_structure.date          = new_rollcall.date;
            vote_structure.yea = new_rollcall.yea;
            vote_structure.nay = new_rollcall.nay;
            vote_structure.nv  = new_rollcall.nv;
            vote_structure.total_vote  = new_rollcall.total_vote;
            vote_structure.yes_percent = new_rollcall.yes_percent;
            vote_structure.yes_list     = new_votelist{new_votelist.vote == obj.VOTE_KEY('yea'),'sponsor_id'};
            vote_structure.no_list      = new_votelist{new_votelist.vote == obj.VOTE_KEY('nay'),'sponsor_id'};
            vote_structure.abstain_list = new_votelist{new_votelist.vote == obj.VOTE_KEY('absent'),'sponsor_id'};
        end
        
        function chamber_data = processChamberRollcalls(obj,chamber_rollcalls,votes_create,committee_threshold)
            
            chamber_data = {};
            
            % chammber_data.committee_id = ??? how do I set this?
            
            committee_votes = obj.getVoteTemplate();
            if sum(chamber_rollcalls.total_vote < committee_threshold) > 0
                committee_votes(sum(chamber_rollcalls.total_vote < committee_threshold)).rollcall_id = 1;
            end
            
            chamber_votes = obj.getVoteTemplate();
            if sum(chamber_rollcalls.total_vote >= committee_threshold)
                chamber_votes(sum(chamber_rollcalls.total_vote >= committee_threshold)).rollcall_id = 1;
            end

            committee_vote_count = 0;
            chamber_vote_count = 0;
            for j = 1:size(chamber_rollcalls,1);
                
                specific_votes = votes_create(votes_create.roll_call_id == chamber_rollcalls{j,'roll_call_id'},:);
                
                if chamber_rollcalls{j,'total_vote'} < committee_threshold; %#ok<BDSCA>
                    committee_vote_count = committee_vote_count + 1;
                    committee_votes(committee_vote_count) = obj.addRollcallVotes(chamber_rollcalls(j,:),specific_votes);
                else % full chamber
                    chamber_vote_count = chamber_vote_count +1;
                    chamber_votes(chamber_vote_count) = obj.addRollcallVotes(chamber_rollcalls(j,:),specific_votes);
                end
            end
            
            chamber_data(end+1).committee_votes = committee_votes;
            chamber_data.chamber_votes = chamber_votes;
            if ~isempty(chamber_votes)
                chamber_data.final_yea = chamber_votes(end).yea;
                chamber_data.final_nay = chamber_votes(end).nay;
                chamber_data.final_nv = chamber_votes(end).nv;
                chamber_data.final_total_vote = chamber_votes(end).total_vote;
                chamber_data.final_yes_percentage = chamber_votes(end).yes_percent;
            else
                chamber_data.final_yes_percentage = -1;
            end
            
        end
        
    end
    
    methods (Static)
        
        function proximity_matrix = processSeatProximity(people)
            % Create the string array list (which allows for referencing variable names
            ids = arrayfun(@(x) ['id' num2str(x)], people{:,'sponsor_id'}, 'Uniform', 0);
            
            x = people{:,'SEATROW'};
            y = people{:,'SEATCOLUMN'};
            dist = sqrt(bsxfun(@minus,x,x').^2 + bsxfun(@minus,y,y').^2);
            
            proximity_matrix = array2table(dist,'RowNames',ids,'VariableNames',ids);
        end
        
        function generateHistograms(people_matrix,save_directory,label_string,specific_label,tag)
            
            rows = people_matrix.Properties.RowNames;
            columns = people_matrix.Properties.VariableNames;
            [~,match_index] = ismember(rows,columns);
            match_index = match_index(match_index > 0);
            
            secondary_plot = nan(1,length(match_index));
            for i = 1:length(match_index)
                secondary_plot(i) = people_matrix{columns{match_index(i)},columns{match_index(i)}};
                people_matrix{columns{match_index(i)},columns{match_index(i)}} = NaN;
            end
            
            main_plot = reshape(people_matrix{:,:},[numel(people_matrix{:,:}),1]);
            
            h = figure();
            hold on
            title(sprintf('%s %s histogram with non-matching legislators',label_string,specific_label))
            xlabel('Agreement')
            ylabel('Frequency')
            grid on
            histfit(main_plot)
            axis([0 1 0 inf])
            hold off
            saveas(h,sprintf('%s/%s_%s_histogram_all',save_directory,label_string,tag),'png')
            
            h = figure();
            hold on
            title(sprintf('%s %s histogram with matching legislators',label_string,specific_label))
            xlabel('Agreement')
            ylabel('Frequency')
            grid on
            histfit(secondary_plot)
            axis([0 1 0 inf])
            hold off
            saveas(h,sprintf('%s/%s_%s_histogram_match',save_directory,label_string,tag),'png')
        end
        
        
        function [people_matrix] = normalizeVotes(people_matrix,vote_matrix)
            % Element-wise divide. This will take divide each value by the
            % possible value (person-vote total)/(possible vote total)
            people_matrix{:,:} = people_matrix{:,:} ./ vote_matrix{:,:};
        end
        
        function makeGif(file_path,save_name,save_path)
            
            results   = dir(sprintf('%s/*.png',file_path));
            file_name = {results(:).name}';
            save_path = [save_path, '\'];
            loops = 65535;
            delay = 0.2;
            
            h = waitbar(0,'0% done','name','Progress') ;
            for i = 1:length(file_name)
                
                a = imread([file_path,file_name{i}]);
                [M,c_map] = rgb2ind(a,256);
                if i == 1
                    imwrite(M,c_map,[save_path,save_name],'gif','LoopCount',loops,'DelayTime',delay)
                else
                    imwrite(M,c_map,[save_path,save_name],'gif','WriteMode','append','DelayTime',delay)
                end
                waitbar(i/length(file_name),h,[num2str(round(100*i/length(file_name))),'% done']) ;
            end
            close(h);
        end
        
        
        function vote_template = getVoteTemplate()
            vote_template = struct('rollcall_id',{},...
                'description',{},...
                'date',{},...
                'yea',{},...
                'nay',{},...
                'nv',{},...
                'total_vote',{},...
                'yes_percent',{},...
                'yes_list',{},...
                'no_list',{},...
                'abstain_list',{});
        end
        
        function chamber_template = getChamberTemplate()
            chamber_template = struct(...
                'committee_id',{},... % make sure multiple comittees are possible
                'committee_votes',{},...
                'chamber_votes',{},...
                'passed',{},...
                'final_yes',{},...
                'final_no',{},...
                'final_abstain',{},...
                'final_yes_percentage',{});
            % final committe and final chamber vote
        end
        
        function bill_template = getBillTemplate()
            bill_template = struct(...
                'bill_id',{},...
                'bill_number',{},...
                'title',{},...
                'issue_category',{},...
                'sponsors',{},... % first vs co, also authors
                'date_introduced',{},...
                'date_of_last_vote',{},...
                'house_data',{},...
                'passed_house',{},...
                'senate_data',{},...
                'passed_senate',{},...
                'passed_both',{},...
                'signed_into_law',{});
            % originated in house/senate?
        end
    end
end